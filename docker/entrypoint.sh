#!/bin/bash
# Entrypoint of the AIQLick Jigasi image: render the configuration, then hand over to the fork's run script.
#
# The upstream jitsi/jigasi image does this in an s6-overlay init script (/etc/cont-init.d/10-config) that runs
# as root. This image has no s6 and runs as an unprivileged user (see the Dockerfile for why), so the same
# rendering lives here. It is a port of that script from jitsi/jigasi:stable-11031, with the same `tpl`
# invocations in the same order, and the Dockerfile fails the build if the two ever render differently.
#
# What was left out on purpose: the timezone symlink (Java reads $TZ itself), the autoscaler sidecar, the Sentry
# release lookup, `chown` (nothing here runs as root), and the Google Cloud key.json (needs jq, and this fork
# transcribes through TranscribeService, not Google).
#
# `--render-only <dir>` renders into <dir> and exits; the Dockerfile uses it for the parity check.

RENDER_ONLY=""
CONFIG_DIR=/config
if [[ "$1" == "--render-only" ]]; then
    RENDER_ONLY=1
    CONFIG_DIR="$2"
    shift 2
fi

if [[ -z "$JIGASI_XMPP_PASSWORD" ]]; then
    echo 'FATAL ERROR: Jigasi auth password must be set'
    exit 1
fi
if [[ "$JIGASI_XMPP_PASSWORD" == "passw0rd" ]]; then
    echo 'FATAL ERROR: Jigasi auth password must be changed, check the README'
    exit 1
fi

[ -z "$JIGASI_MODE" ] && JIGASI_MODE="sip"
JIGASI_MODE="$(echo "$JIGASI_MODE" | tr '[:upper:]' '[:lower:]')"

if [[ "$JIGASI_MODE" == "transcriber" ]]; then
    # set random jigasi nickname for the instance if is not set
    [ -z "${JIGASI_INSTANCE_ID}" ] && export JIGASI_INSTANCE_ID="transcriber-$(date +%N)"
fi

# set random jigasi nickname for the instance if is not set
[ -z "${JIGASI_INSTANCE_ID}" ] && export JIGASI_INSTANCE_ID="jigasi-$(date +%N)"

# set stats id for the instance
[ -z "${JIGASI_STATS_ID}" ] && export JIGASI_STATS_ID="$JIGASI_INSTANCE_ID"

# maintain backward compatibility with older variable
[ -z "${XMPP_HIDDEN_DOMAIN}" ] && export XMPP_HIDDEN_DOMAIN="$XMPP_RECORDER_DOMAIN"

render()
{
    # A failed render must stop the container. The upstream script ignores it and starts Jigasi on a
    # half-written config, which then fails later and further from the cause.
    local template="$1" mode="$2" target="$3"
    if [[ "$mode" == "append" ]]; then
        tpl "$template" >> "$target" || { echo "FATAL ERROR: could not render $template"; exit 1; }
    else
        tpl "$template" > "$target" || { echo "FATAL ERROR: could not render $template"; exit 1; }
    fi
}

mkdir -p "$CONFIG_DIR" || { echo "FATAL ERROR: cannot create $CONFIG_DIR"; exit 1; }

render /defaults/logging.properties write "$CONFIG_DIR/logging.properties"
render /defaults/sip-communicator.properties write "$CONFIG_DIR/sip-communicator.properties"
render /defaults/xmpp-sip-communicator.properties append "$CONFIG_DIR/sip-communicator.properties"

if [[ "$JIGASI_MODE" == "sip" ]]; then
    render /defaults/sipserver-sip-communicator.properties append "$CONFIG_DIR/sip-communicator.properties"
elif [[ "$JIGASI_MODE" == "transcriber" ]]; then
    render /defaults/transcriber-sip-communicator.properties append "$CONFIG_DIR/sip-communicator.properties"
    [ -z "$RENDER_ONLY" ] && mkdir -p /tmp/transcripts

    if [[ -z "$GC_PROJECT_ID" || -z "$GC_PRIVATE_KEY_ID" || -z "$GC_PRIVATE_KEY" || -z "$GC_CLIENT_EMAIL" || -z "$GC_CLIENT_ID" || -z "$GC_CLIENT_CERT_URL" ]]; then
        echo 'Transcriptions: One or more gcloud environment variables are undefined, skipping gcloud credentials file /config/key.json'
    else
        echo 'WARNING: GC_* credentials are set, but this image does not write /config/key.json (no jq); Google Cloud transcription is not available here'
    fi
fi

if [[ -f "$CONFIG_DIR/custom-sip-communicator.properties" ]]; then
    cat "$CONFIG_DIR/custom-sip-communicator.properties" >> "$CONFIG_DIR/sip-communicator.properties"
fi
if [[ -f "$CONFIG_DIR/custom-logging.properties" ]]; then
    cat "$CONFIG_DIR/custom-logging.properties" >> "$CONFIG_DIR/logging.properties"
fi

[ -n "$RENDER_ONLY" ] && exit 0

exec /usr/local/bin/jigasi-run "$@"
