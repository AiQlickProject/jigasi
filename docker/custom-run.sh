#!/usr/bin/with-contenv bash
# Custom Jigasi run script with ice4j configuration
# This script configures ICE candidates to restrict Docker bridge IPs

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
