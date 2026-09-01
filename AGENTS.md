# jigasi

Java 11 + Maven (custom Jitsi Jigasi fork). Transcription/SIP gateway for Jitsi Meet.

Custom fork adds `user_id` support in transcription WebSocket header and custom ICE4J NAT config for AWS EC2.

Key rules in `CLAUDE.md` — read it first.

## Commands

`mvn package -DskipTests` — build JAR (skip tests)
`mvn test` — run tests
`mvn verify -B -Pcoverage` — CI full verification with JaCoCo
`docker build -t aiqlick-jigasi:latest .` — Docker image

## Architecture

Jitsi Prosody (XMPP) → Jigasi → WebSocket (audio + `user_id`) → `background-tasks` (at `wss://api.aiqlick.com/transcription/ws`) → AWS Transcribe → PostgreSQL.

Primary transcription provider: `TranscribeService` (WebSocket to background-tasks). Also has Google Cloud, Vosk, and Oracle providers.

## Deploy

Push to `main`/`master` → CI/CD builds ECR image → SSM sends command to EC2 (`i-0620d2e23695f5bfc`) → `docker compose up -d --force-recreate jigasi`.

ECR: `842697652860.dkr.ecr.eu-north-1.amazonaws.com/aiqlick-jigasi`.

See `CLAUDE.md` for full source layout, CI matrix (Java 11/17/21), and transcription flow.
- **Before debugging a failing fix, prove your code is deployed.** Match the deploy run on `headSha`, not recency (`--limit 1` often returns the previous commit's run), and grep the running artifact for something unique to the change. Diagnose every layer in one pass with labelled output rather than one fix per deploy — and never `try/catch` the probe, it hides the answer.
