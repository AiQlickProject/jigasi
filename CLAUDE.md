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
# Maven CI runs on PRs (Java 11, 17, 21)
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

Multi-stage build:
1. **Builder** (`maven:3.9-eclipse-temurin-11`): Compiles JAR with dependencies
2. **Runtime** (`jitsi/jigasi:stable-9823`): Copies custom JAR over official one + custom run script

The base image provides all Jigasi runtime dependencies in `/usr/share/jigasi/lib/`.

## Key Files

| File | Purpose |
|------|---------|
| `src/main/java/org/jitsi/jigasi/` | Main source — `JvbConference.java` (Colibri WebSocket + Jingle handling), `TranscriptionGateway.java`, `Transcriber.java` |
| `src/main/java/net/java/sip/communicator/impl/protocol/jabber/` | XMPP protocol implementation |
| `docker/custom-run.sh` | Runtime config script — ICE4J NAT harvester + transcription setup |
| `jigasi-home/sip-communicator.properties` | Template for SIP/XMPP config (populated at runtime) |
| `pom.xml` | Maven build config (Java 11 source/target) |

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

- **ECR**: `842697652860.dkr.ecr.eu-north-1.amazonaws.com/aiqlick-jigasi`
- **CI/CD**: Push to `main` or `master` → build Docker → push to ECR → SSM redeploy on Jitsi EC2
- **EC2**: t3.xlarge (4 vCPU, 16GB RAM), 16.16.21.64 (Elastic IP), 20GB EBS
- **Container limits**: 1.5 GB memory, JVM heap 1024m (`JIGASI_MAX_MEMORY`)
- **Ports**: UDP 20000-20050 (RTP media)
- **Healthcheck**: `ls /proc/1/status` (container lacks curl/pgrep)
- **Log rotation**: json-file driver, 10m max-size, 3 files
- **Related repos**: `jitsi-deploy` (Docker Compose config), `background-tasks` (transcription WebSocket handler)

### Runtime on EC2

Jigasi runs as one of 7 containers in `jitsi-deploy`:
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
