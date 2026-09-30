# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Custom fork of [Jitsi Jigasi](https://github.com/jitsi/jigasi) — a transcription and SIP gateway for Jitsi Meet. Our fork adds `user_id` support in the transcription WebSocket header and custom ICE4J NAT configuration for AWS EC2 deployment.

**Live deployment**: Part of Jitsi stack at `book.aiqlick.com` (EC2 t3.xlarge, 16.16.21.64, Elastic IP)

## Commands

### Build
```bash
# Build JAR (with assembly for distribution)
mvn install -Dassembly.skipAssembly=false

# Build JAR (skip tests for speed)
mvn package -DskipTests -Dassembly.skipAssembly=false

# Run tests
mvn test

# Build Docker image
docker build -t aiqlick-jigasi:latest .
```

### CI/CD
```bash
# Maven CI runs on PRs (Java 17, 21, 25)
# ECR deploy runs on push to main

# Manual ECR build + deploy
gh workflow run ecr-deploy.yml
```

## Architecture

```
Jitsi Prosody (XMPP)
    ↓
Jigasi (this repo)
    ↓ WebSocket (audio stream + user_id header)
background-tasks (wss://api.aiqlick.com/transcription/ws)
    ↓
AWS Transcribe (eu-west-1)
    ↓
Transcription records in PostgreSQL
```

**Key flow**: Jicofo detects Jigasi in `JigasiBrewery` MUC room → invites Jigasi to conference as hidden participant → Jigasi receives audio → streams to background-tasks via WebSocket → captions broadcast back to participants.

## Docker Build

Multi-stage build, and the image runs as an unprivileged user (uid 10001) with no s6:
1. **Builder** (`maven:3.9-eclipse-temurin-17`): `mvn package -Dassembly.skipAssembly=false` produces the distribution
   (`jigasi.jar`, `jigasi.sh`, `lib/*.jar` resolved from `pom.xml`, pins included). The build fails if the jar is not the fork.
2. **Upstream reference** (`jitsi/jigasi:stable-11031`): only a source for the `tpl` renderer and the `/defaults` config
   templates, and a reference the runtime stage's rendering is diffed against.
3. **Runtime** (`eclipse-temurin:17-jre-noble`): the assembly, `tpl`, `/defaults`, `docker/entrypoint.sh` (renders the config,
   port of upstream's s6 init script) and `docker/custom-run.sh` (the fork's ICE4J/transcription script).

The image ships **exactly the dependency set of `pom.xml`**, so the security pins in `pom.xml` are what runs. It used to copy
a thin jar onto `jitsi/jigasi`, whose own `lib/` (older jackson, kotlin, jicoco) then loaded instead. When moving to a newer
upstream release, bump the tag in the `upstream-reference` stage only; the build fails if the rendered config differs.

## Key Files

| File | Purpose |
|------|---------|
| `src/main/java/org/jitsi/jigasi/` | Main source — `JvbConference.java` (Colibri WebSocket + Jingle handling), `TranscriptionGateway.java`, `Transcriber.java` |
| `src/main/java/net/java/sip/communicator/impl/protocol/jabber/` | XMPP protocol implementation |
| `docker/entrypoint.sh` | Image entrypoint — renders `/config` from `/defaults` (port of upstream's `10-config`), then runs `custom-run.sh` |
| `docker/custom-run.sh` | Runtime config script — ICE4J NAT harvester + transcription setup |
| `docker/parity.env` | Placeholder env for the Dockerfile's config-parity check |
| `jigasi-home/sip-communicator.properties` | Template for SIP/XMPP config (populated at runtime) |
| `pom.xml` | Maven build config (Java 17 release; dependency security pins in `dependencyManagement`) |

## Transcription Services

Available providers in `src/main/.../transcription/`:
- **TranscribeService** — Our primary: WebSocket to background-tasks
- GoogleCloudTranscriptionService — Google Cloud Speech
- VoskTranscriptionService — Vosk offline
- OracleTranscriptionService — Oracle Cloud

## Environment Variables

Set in `docker/custom-run.sh` and `jitsi-deploy/docker-compose.yml`:

**ICE4J (NAT/Network):**
- `ICE4J_LOCAL_ADDRESS` — Local IP for NAT harvester (auto-detected if unset)
- `ICE4J_PUBLIC_ADDRESS` — Public IP (auto-detected from EC2 metadata)
- `ICE4J_ALLOWED_INTERFACES` — Semicolon-separated interface names (e.g., `ens5;eth0`)

**Transcription:**
- `JIGASI_ENABLE_TRANSCRIPTION` — `true` to enable (disables SIP)
- `JIGASI_TRANSCRIPTION_SERVICE` — Service class (default: TranscribeService)
- `JIGASI_TRANSCRIBER_URL` — WebSocket URL (e.g., `wss://api.aiqlick.com/transcription/ws`)
- `JIGASI_TRANSCRIBER_PRIVATE_KEY` — Base64 private key for JWT auth (optional)

**XMPP:**
- `XMPP_SERVER` — Prosody server (default: `meet.jitsi`)
- `JIGASI_XMPP_USER` / `JIGASI_XMPP_PASSWORD` — XMPP auth
- `XMPP_MUC_DOMAIN` — MUC domain for brewery rooms

## Deployment

- **Registry**: `ghcr.io/aiqlickproject/jigasi`, tagged `dev-<full commit sha>` (`latest` moves only on master and must never be pinned).
  The ECR repository and the EC2 host this section used to describe are retired.
- **CI/CD**: push to `master` (or a manual `ghcr-build.yml` dispatch on any branch) builds and pushes the image. **Nothing deploys
  from this repo**: the running image is the pin in `aiqlick-meeting/k8s/jitsi/90-jigasi.yaml` (prod, namespace `meeting`); dev
  (`meeting-dev`) is applied separately. Rolling it restarts Jigasi (Recreate strategy) and ends in-flight transcription sessions.
- **Runs on**: the Swedish RKE2 cluster, as uid 10001 (`runAsNonRoot` compatible), no s6, no capabilities needed.
- **Container limits**: 2Gi memory limit, JVM heap 1024m (`JIGASI_MAX_MEMORY`)
- **Ports**: UDP 20000-20050 (RTP media), cluster-internal only
- **Health**: the Kubernetes probes grep `/proc/net/tcp*` for an ESTABLISHED connection to the XMPP port (Jigasi's own
  `/about/health` is a constant 200 in transcriber mode). The image must keep `sh`, `grep` and procfs.
- **Related repos**: `aiqlick-meeting` (`k8s/jitsi/` manifests and the pin), `jitsi-deploy` (legacy Docker Compose config),
  `background-tasks` (transcription WebSocket handler)

### Runtime

Jigasi is one of the Jitsi services (prosody, jicofo, jvb, web, coturn, jigasi):
- Registers in `JigasiBrewery` MUC → Jicofo discovers it
- Joins conferences as hidden participant (via `hidden.meet.jitsi` domain)
- Streams audio to `wss://api.aiqlick.com/transcription/ws` via TranscribeService
- Requires `JIGASI_ALWAYS_USE_JVB=true` and `JIGASI_DISABLE_P2P=true` (container environments don't support P2P)
- Does NOT need `ICE4J_PUBLIC_ADDRESS` — only communicates with JVB on Docker network

### Colibri WebSocket (JvbConference.java)

Jigasi must establish a Colibri WebSocket connection with JVB for audio forwarding. The URL is extracted from Jingle session-initiate/transport-info IQs via regex.

**Known issue (fixed):** Smack XMPP library re-serializes parsed IQs, moving `xmlns` from child `<web-socket>` to parent `<transport>` element (namespace inheritance). The extraction uses a relaxed fallback regex + retry mechanism (5 attempts, 2s apart) to handle this.

JVB's `first-transfer-timeout` is extended to 120s (from default 15s) via `custom-jvb.conf` in `jitsi-deploy` repo as a safety net.

## Git Workflow

```bash
# NEVER push directly to master
git checkout dev
git add . && git commit -m "feat: description"
git push origin dev
# Create PR: dev → master, merge triggers ECR deploy
```

## Before debugging a failing fix: prove your code is deployed

When a change "still fails" in dev or prod, the first question is **is my code actually
running there** — not "what else is wrong with my code". Three debug cycles were spent on
2026-08-25 fixing code that was never in the running image.

- **Match the deploy run to the commit, not to recency.** `gh run list --limit 1` returns
  the newest run, which is frequently for the *previous* commit:
  `gh run list --branch <b> --workflow "<w>" --limit 5 --json databaseId,headSha,status,conclusion`
- **Grep the running artifact** for a string unique to the change. On the Swedish cluster the
  image tag carries the full SHA:
  `kubectl -n <ns> get deploy <d> -o jsonpath='{.spec.template.spec.containers[0].image}'`
- **Diagnose in one pass, not one fix per deploy.** Print every layer as labelled facts
  (`D1=`, `D2=`, …) in a single run. Eleven labelled facts in ~90 seconds replaced eight PRs
  and revealed three stacked causes that could only surface one at a time.
- **Never wrap the diagnostic path in `try/catch`** — it swallows the error that would have
  named the layer. Defensive handling belongs in the fix, not the probe.

## Watching a long job (workspace rule)

Break a monitor on **process absence** (`pgrep -f '<script>' >/dev/null || break`),
never on a log marker — a job that dies a way you did not enumerate otherwise
polls forever, and silence is indistinguishable from progress. One watcher per
subject. Never pipe a long job through `| tail -N` (it buffers until exit, so a
hang looks like work — use `tee -a`). `kill -9` leaves a finalizer-dependent job,
such as a W&B run, showing `running`; send SIGTERM first. And never act
destructively on one early datapoint — read the trend.

## CI completion and smoke-test evidence

- Match deployment and CI/security runs to the exact commit separately. A successful deployment does not make queued checks green. Inspect `gh api repos/<owner>/<repo>/actions/runs/<id>/jobs`: a run can remain `queued` while individual jobs are running or already successful. Check eligible runner labels and busy state before restarting runners or changing workflows.
- Cancel an obsolete promotion-PR run only after confirming the PR is merged and equivalent checks remain on the intended commit. Preserve the actual production checks and unrelated work; never cancel a unique security gate to finish faster.
- A short-lived probe can exit before an attached client captures stdout. Empty output is inconclusive, not proof of an HTTP/auth failure. Wait for container termination, read persisted logs and its exit code, and enforce the expected status AND body size. Keep transport failures distinct and fail closed.
- Read the failed step before retrying. A wall-clock threshold can be affected by runner contention; one unchanged rerun of the failed job can establish whether it repeats. A passing retry does not prove every timing failure harmless. Investigate recurring failures without widening thresholds, skipping assertions, or suppressing scanner findings.

Verified 2026-09-08: backend CI run `34210498184` progressed at job level while queued; docs run `34211487120` enforced `302 0` from completed-pod logs; backend dev run `34209852994` passed its failed timing shard unchanged on attempt 2.
