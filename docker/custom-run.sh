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

# Auto-detect local IP if not set (for EC2/cloud deployments)
if [ -z "$ICE4J_LOCAL_ADDRESS" ]; then
    # Try to get the primary non-docker IP
    ICE4J_LOCAL_ADDRESS=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[0-9.]+' || hostname -I | awk '{print $1}')
fi

# Auto-detect public IP if not set (for EC2 instances)
if [ -z "$ICE4J_PUBLIC_ADDRESS" ]; then
    # Try EC2 metadata first, then external service
    ICE4J_PUBLIC_ADDRESS=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || \
                           curl -s --connect-timeout 2 https://checkip.amazonaws.com 2>/dev/null || \
                           echo "")
fi

# NAT Harvester configuration (required for EC2/cloud behind NAT)
if [ -n "$ICE4J_LOCAL_ADDRESS" ] && [ -n "$ICE4J_PUBLIC_ADDRESS" ]; then
    echo "Configuring NAT Harvester: local=$ICE4J_LOCAL_ADDRESS public=$ICE4J_PUBLIC_ADDRESS"
    JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.NAT_HARVESTER_LOCAL_ADDRESS=${ICE4J_LOCAL_ADDRESS}"
    JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS=${ICE4J_PUBLIC_ADDRESS}"
fi

# Allowed interfaces - use specific interface name (e.g., eth0, ens5) for reliable binding
# For EC2: typically ens5 or eth0. For Docker host mode, use the host's primary interface.
if [ -n "$ICE4J_ALLOWED_INTERFACES" ]; then
    JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.ALLOWED_INTERFACES=${ICE4J_ALLOWED_INTERFACES}"
fi

# Allowed addresses - restrict to specific IPs if set
if [ -n "$ICE4J_ALLOWED_ADDRESSES" ]; then
    JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.ALLOWED_ADDRESSES=${ICE4J_ALLOWED_ADDRESSES}"
fi

# Blocked addresses - block Docker bridges and k3s pod network by default
ICE4J_BLOCKED="${ICE4J_BLOCKED_ADDRESSES:-}"
if [ -n "$ICE4J_BLOCKED" ]; then
    JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.BLOCKED_ADDRESSES=${ICE4J_BLOCKED}"
fi

# Disable IPv6 (causes issues in Docker/cloud environments)
JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ipv6.DISABLED=true"

# Disable link-local IPv6 addresses (not routable)
JAVA_SYS_PROPS="$JAVA_SYS_PROPS -Dorg.ice4j.ice.harvest.USE_LINK_LOCAL_ADDRESSES=false"

DAEMON=/usr/share/jigasi/jigasi.sh
DAEMON_OPTS="--nocomponent=true --configdir=/ --configdirname=config --min-port=${JIGASI_PORT_MIN:-20000} --max-port=${JIGASI_PORT_MAX:-20050}"

# Export JAVA_SYS_PROPS so jigasi.sh can use it
export JAVA_SYS_PROPS

# Log the ice4j configuration for debugging
echo "ICE4J Configuration:"
echo "  LOCAL_ADDRESS: ${ICE4J_LOCAL_ADDRESS:-auto}"
echo "  PUBLIC_ADDRESS: ${ICE4J_PUBLIC_ADDRESS:-auto}"
echo "  ALLOWED_INTERFACES: ${ICE4J_ALLOWED_INTERFACES:-all}"
echo "  ALLOWED_ADDRESSES: ${ICE4J_ALLOWED_ADDRESSES:-all}"
echo "  BLOCKED_ADDRESSES: ${ICE4J_BLOCKED:-none}"
echo "  JAVA_SYS_PROPS: ${JAVA_SYS_PROPS}"

# Run jigasi with s6-setuidgid (drops to jigasi user)
if [ -n "$JIGASI_LOG_FILE" ]; then
    exec s6-setuidgid jigasi $DAEMON $DAEMON_OPTS 2>&1 | tee $JIGASI_LOG_FILE
else
    exec s6-setuidgid jigasi $DAEMON $DAEMON_OPTS
fi
