# Custom Jigasi with user_id support in transcription header
# Build: docker build -t ghcr.io/aiqlickproject/jigasi:custom-userid .

# Multi-stage build - Maven builder
FROM maven:3.9-eclipse-temurin-11 AS builder

WORKDIR /build

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -B || true

# Copy source code
COPY src ./src
COPY lib ./lib

# Build JAR (skip tests for faster build)
RUN mvn package -DskipTests -Dassembly.skipAssembly=false

# Runtime image - extend official Jigasi
FROM jitsi/jigasi:stable-9823

# Copy custom JAR over official one
# The base image already has dependencies in /usr/share/jigasi/lib/
COPY --from=builder /build/target/jigasi-1.1-SNAPSHOT.jar /usr/share/jigasi/jigasi.jar

# Copy custom run script with ice4j and transcription configuration
# Environment variables for ICE4J (NAT/network configuration):
#   ICE4J_LOCAL_ADDRESS - Local IP address for NAT harvester (auto-detected if not set)
#   ICE4J_PUBLIC_ADDRESS - Public IP address for NAT harvester (auto-detected from EC2 metadata)
#   ICE4J_ALLOWED_INTERFACES - Semicolon-separated interface names (e.g., ens5;eth0)
#   ICE4J_ALLOWED_ADDRESSES - Semicolon-separated list of allowed IPs
#   ICE4J_BLOCKED_ADDRESSES - Semicolon-separated list of blocked IPs
# Environment variables for Transcription:
#   JIGASI_ENABLE_TRANSCRIPTION - Set to "true" to enable transcription mode (disables SIP)
#   JIGASI_TRANSCRIPTION_SERVICE - Custom transcription service class (default: WhisperTranscriptionService)
#   JIGASI_WHISPER_WEBSOCKET_URL - WebSocket URL for Whisper service (e.g., wss://ai.aiqlick.com/transcription/ws)
#   JIGASI_WHISPER_PRIVATE_KEY - Base64 encoded private key for JWT auth (optional)
#   JIGASI_WHISPER_PRIVATE_KEY_NAME - Private key name for JWT auth (optional)
#   JIGASI_WHISPER_JWT_AUDIENCE - JWT audience (optional, default: jitsi)
COPY docker/custom-run.sh /etc/services.d/jigasi/run
RUN chmod +x /etc/services.d/jigasi/run

# Labels
LABEL org.opencontainers.image.title="AIQLick Custom Jigasi"
LABEL org.opencontainers.image.description="Jigasi with user_id in transcription header"
LABEL org.opencontainers.image.source="https://github.com/AiQlickProject/jigasi"
LABEL org.opencontainers.image.vendor="AIQLick"
