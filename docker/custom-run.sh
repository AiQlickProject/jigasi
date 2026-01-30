#!/usr/bin/with-contenv bash
# Custom Jigasi run script with ice4j and transcription configuration
# This script configures ICE candidates and transcription settings

# ==============================================================================
# TRANSCRIPTION CONFIGURATION
# ==============================================================================
# Write transcription properties to sip-communicator.properties
# These must be in the properties file as ConfigurationService reads from there

SIP_PROPS="/config/sip-communicator.properties"

# Function to set property in sip-communicator.properties
set_prop() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$SIP_PROPS" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$SIP_PROPS"
    else
        echo "${key}=${value}" >> "$SIP_PROPS"
    fi
}

# Enable transcription if JIGASI_ENABLE_TRANSCRIPTION is set
if [ -n "$JIGASI_ENABLE_TRANSCRIPTION" ] && [ "$JIGASI_ENABLE_TRANSCRIPTION" = "true" ]; then
    echo "Enabling transcription mode..."
    set_prop "org.jitsi.jigasi.ENABLE_TRANSCRIPTION" "true"
    set_prop "org.jitsi.jigasi.ENABLE_SIP" "false"

    # Set custom transcription service (WhisperTranscriptionService)
    if [ -n "$JIGASI_TRANSCRIPTION_SERVICE" ]; then
        set_prop "org.jitsi.jigasi.transcription.customService" "$JIGASI_TRANSCRIPTION_SERVICE"
    else
        set_prop "org.jitsi.jigasi.transcription.customService" "org.jitsi.jigasi.transcription.WhisperTranscriptionService"
    fi

    # Set Whisper WebSocket URL
    if [ -n "$JIGASI_WHISPER_WEBSOCKET_URL" ]; then
        set_prop "org.jitsi.jigasi.transcription.whisper.websocket_url" "$JIGASI_WHISPER_WEBSOCKET_URL"
    fi

    # Optional: JWT settings for authenticated Whisper service
    if [ -n "$JIGASI_WHISPER_PRIVATE_KEY" ]; then
        set_prop "org.jitsi.jigasi.transcription.whisper.private_key" "$JIGASI_WHISPER_PRIVATE_KEY"
    fi
    if [ -n "$JIGASI_WHISPER_PRIVATE_KEY_NAME" ]; then
        set_prop "org.jitsi.jigasi.transcription.whisper.private_key_name" "$JIGASI_WHISPER_PRIVATE_KEY_NAME"
    fi
    if [ -n "$JIGASI_WHISPER_JWT_AUDIENCE" ]; then
        set_prop "org.jitsi.jigasi.transcription.whisper.jwt_audience" "$JIGASI_WHISPER_JWT_AUDIENCE"
    fi

    echo "Transcription configuration:"
    grep -E "^org.jitsi.jigasi.(ENABLE_|transcription)" "$SIP_PROPS" 2>/dev/null || true
fi

# ==============================================================================
# ICE4J CONFIGURATION
# ==============================================================================
# Configure ice4j via Java system properties
# HOCON -Dconfig.file doesn't work because JitsiConfig.useDebugNewConfig() replaces it
# Using org.ice4j.ice.harvest.* legacy properties which are read directly by ice4j
# Reference: https://github.com/jitsi/ice4j/blob/master/doc/configuration.md

JAVA_SYS_PROPS="-Djava.util.logging.config.file=/config/logging.properties"

# ICE allowed addresses - restrict to host LAN IP only
# This prevents Docker bridge IPs from being advertised as ICE candidates
# Override with ICE4J_ALLOWED_ADDRESSES environment variable if needed
ICE4J_ALLOWED="${ICE4J_ALLOWED_ADDRESSES:-192.168.1.250}"
JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.ALLOWED_ADDRESSES=${ICE4J_ALLOWED}"

# ICE blocked addresses - block Docker bridges and k3s pod network
# These are internal IPs that JVB cannot reach
ICE4J_BLOCKED="${ICE4J_BLOCKED_ADDRESSES:-172.17.0.1;172.18.0.1;172.19.0.1;172.20.0.1;172.21.0.1;172.22.0.1;172.23.0.1;10.42.0.1}"
JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.BLOCKED_ADDRESSES=${ICE4J_BLOCKED}"

# Disable link-local IPv6 addresses (not routable)
JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.USE_LINK_LOCAL_ADDRESSES=false"

DAEMON=/usr/share/jigasi/jigasi.sh
DAEMON_OPTS="--nocomponent=true --configdir=/ --configdirname=config --min-port=${JIGASI_PORT_MIN:-20000} --max-port=${JIGASI_PORT_MAX:-20050}"

# Export JAVA_SYS_PROPS so jigasi.sh can use it
export JAVA_SYS_PROPS

# Log the ice4j configuration for debugging
echo "ICE4J Configuration:"
echo "  ALLOWED_ADDRESSES: ${ICE4J_ALLOWED}"
echo "  BLOCKED_ADDRESSES: ${ICE4J_BLOCKED}"
echo "  JAVA_SYS_PROPS: ${JAVA_SYS_PROPS}"

# Run jigasi with s6-setuidgid (drops to jigasi user)
if [ -n "$JIGASI_LOG_FILE" ]; then
    exec s6-setuidgid jigasi $DAEMON $DAEMON_OPTS 2>&1 | tee $JIGASI_LOG_FILE
else
    exec s6-setuidgid jigasi $DAEMON $DAEMON_OPTS
fi
