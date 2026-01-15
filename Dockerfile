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
# The jar-with-dependencies includes all required libraries
COPY --from=builder /build/target/jigasi-*-jar-with-dependencies.jar /usr/share/jigasi/jigasi.jar

# Labels
LABEL org.opencontainers.image.title="AIQLick Custom Jigasi"
LABEL org.opencontainers.image.description="Jigasi with user_id in transcription header"
LABEL org.opencontainers.image.source="https://github.com/AiQlickProject/jigasi"
LABEL org.opencontainers.image.vendor="AIQLick"
