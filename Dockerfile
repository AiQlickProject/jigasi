# syntax=docker/dockerfile:1
#
# AIQLick Jigasi: the fork, built from source, on a plain JRE, running as an unprivileged user.
# Build: docker build --platform linux/amd64 -t ghcr.io/aiqlickproject/jigasi:custom .
#
# This used to be `FROM jitsi/jigasi` with the fork's jar copied over the one in the base image. It no longer is,
# for three reasons that all come from that base and could not be fixed while it stayed the base:
#
#  1. The base runs under s6-overlay v2, whose init must be root, so the image could not declare a non-root
#     USER (Trivy DS-0002). Here there is no s6: Jigasi is PID 1, started by docker/entrypoint.sh.
#  2. The base's lib/ is upstream's own dependency set (jackson-databind 2.12.6.1, kotlin 1.9, jicoco 1.1-170,
#     Jetty of its own release), older than this fork's pom. Copying a jar compiled against the pom's versions
#     onto it ran the fork against libraries it was never built with, and made every pin in pom.xml cosmetic:
#     what ran was whatever the base shipped. This image ships the assembly's lib/, i.e. exactly the pom.
#  3. The base is Debian 12 with roughly 200 HIGH/CRITICAL OS findings; eclipse-temurin's JRE on Ubuntu
#     24.04 has none after `apt-get upgrade`.
#
# What is still taken from upstream's image, and pinned to one release: the /defaults configuration templates. The
# `upstream-reference` stage also renders them with upstream's own init script and binary, and the last RUN below
# fails the build if docker/entrypoint.sh (with the `tpl` built here) renders anything different. Bump the tag in
# that stage and in nothing else when moving to a newer upstream release.
#
# Environment variables (unchanged from the previous image):
#   ICE4J_LOCAL_ADDRESS / ICE4J_PUBLIC_ADDRESS - NAT harvester addresses (auto-detected if not set)
#   ICE4J_ALLOWED_INTERFACES, ICE4J_ALLOWED_ADDRESSES, ICE4J_BLOCKED_ADDRESSES - semicolon-separated
#   JIGASI_ENABLE_TRANSCRIPTION - "true" enables transcription mode (disables SIP)
#   JIGASI_TRANSCRIPTION_SERVICE - custom transcription service class (default: TranscribeService)
#   JIGASI_TRANSCRIBER_URL - WebSocket URL of the Transcribe service
#   JIGASI_TRANSCRIBER_PRIVATE_KEY / _PRIVATE_KEY_NAME / _JWT_AUDIENCE - JWT settings (optional)
# plus everything upstream's templates read (XMPP_*, JIGASI_XMPP_*, JIGASI_MODE, ...).

# ---- build the fork ----------------------------------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# pom.xml first, so the dependency download is a cached layer
COPY pom.xml .
RUN mvn dependency:go-offline -B || true

COPY src ./src
COPY lib ./lib
COPY script ./script
COPY jigasi.sh ./

# The distribution assembly: jigasi.jar, jigasi.sh and lib/*.jar resolved from pom.xml, pins included.
RUN mvn package -B -DskipTests -Dassembly.skipAssembly=false

WORKDIR /out
RUN jar xf /build/target/jigasi-linux-x64-*.zip \
 && mv /out/jigasi-linux-x64-* /out/jigasi \
 && chmod 0755 /out/jigasi/jigasi.sh /out/jigasi/graceful_shutdown.sh

# Fail here, not in the cluster, if this is not the fork or if it picked up another OS's native libraries.
RUN jar tf /out/jigasi/jigasi.jar > /tmp/jigasi-jar.txt \
 && grep -q 'org/jitsi/jigasi/transcription/TranscribeService\.class' /tmp/jigasi-jar.txt \
 && grep -q 'org/jitsi/jigasi/xmpp/ColibriWebSocketClient\.class' /tmp/jigasi-jar.txt \
 && ls /out/jigasi/lib | grep -q '^jitsi-lgpl-dependencies-' \
 && ! ls /out/jigasi/lib | grep -Eq 'darwin|macosx|windows'

# ---- the `tpl` config renderer -------------------------------------------------------------------------------
# github.com/jitsi/tpl is what upstream's init script calls. The binary in upstream's image was built in April 2025
# with Go 1.24.0 and golang.org/x/crypto 0.33.0 (Trivy: 1 CRITICAL and 35 HIGH), so it is rebuilt here from the same
# commit with a current toolchain and the two vulnerable modules bumped. The parity check at the end of this file is
# what proves the rebuilt binary still renders the same output.
FROM golang:1.26-bookworm AS tpl
ARG TPL_COMMIT=f887c7d4bd09425e6f4ab5cea0e39ca826b5b3a2
WORKDIR /src
RUN git clone https://github.com/jitsi/tpl . \
 && git checkout ${TPL_COMMIT}
RUN go get golang.org/x/crypto@latest golang.org/x/text@latest \
 && go mod tidy \
 && CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/tpl .

# ---- upstream's templates, rendered the way upstream renders them ------------------------------------------
FROM jitsi/jigasi:stable-11031 AS upstream-reference

# /config is a volume of the upstream image, created by `docker run` and absent at build time.
RUN --mount=type=bind,source=docker/parity.env,target=/parity.env \
    set -e; \
    mkdir -p /config; \
    for mode in sip transcriber; do \
      ( set -a; . /parity.env; JIGASI_MODE=$mode; set +a; bash /etc/cont-init.d/10-config > /dev/null ); \
      mkdir -p /rendered/$mode; \
      cp /config/logging.properties /config/sip-communicator.properties /rendered/$mode/; \
    done

# ---- runtime -----------------------------------------------------------------------------------------------
FROM eclipse-temurin:17-jre-noble

# Patch the OS packages the base image was built with (the base is a few weeks behind Ubuntu's security pocket),
# add `ip`, which the fork's run script prefers for local-address detection, and libasound, which the upstream image
# has and libjnportaudio.so links against (the other native libraries' gaps are the same as upstream's).
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends iproute2 libasound2t64 \
 && rm -rf /var/lib/apt/lists/*

# A numeric id, so Kubernetes' runAsNonRoot can verify it without resolving a name.
RUN groupadd --gid 10001 jigasi \
 && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /usr/share/jigasi --shell /usr/sbin/nologin jigasi

COPY --from=tpl /out/tpl /usr/local/bin/tpl
COPY --from=upstream-reference /defaults /defaults
COPY --from=builder --chown=10001:10001 /out/jigasi /usr/share/jigasi
COPY docker/entrypoint.sh /usr/local/bin/jigasi-entrypoint
COPY docker/custom-run.sh /usr/local/bin/jigasi-run

# /config and /tmp/transcripts are emptyDir mounts in the cluster; they are created here for `docker run`.
RUN chmod 0755 /usr/local/bin/jigasi-entrypoint /usr/local/bin/jigasi-run \
 && mkdir -p /config /tmp/transcripts \
 && chown 10001:10001 /config /tmp/transcripts

# The port of upstream's init script must render what upstream renders, in both modes.
RUN --mount=type=bind,source=docker/parity.env,target=/parity.env \
    --mount=type=bind,from=upstream-reference,source=/rendered,target=/parity-reference \
    set -e; \
    for mode in sip transcriber; do \
      ( set -a; . /parity.env; JIGASI_MODE=$mode; set +a; /usr/local/bin/jigasi-entrypoint --render-only /tmp/parity-$mode > /dev/null ); \
      diff -u /parity-reference/$mode/logging.properties /tmp/parity-$mode/logging.properties; \
      diff -u /parity-reference/$mode/sip-communicator.properties /tmp/parity-$mode/sip-communicator.properties; \
    done; \
    rm -rf /tmp/parity-*

LABEL org.opencontainers.image.title="AIQLick Custom Jigasi"
LABEL org.opencontainers.image.description="Jigasi fork (Transcribe websocket, Colibri websocket) on a plain JRE, unprivileged"
LABEL org.opencontainers.image.source="https://github.com/AiQlickProject/jigasi"
LABEL org.opencontainers.image.vendor="AIQLick"

WORKDIR /usr/share/jigasi
ENV HOME=/usr/share/jigasi
USER 10001:10001
ENTRYPOINT ["/usr/local/bin/jigasi-entrypoint"]
