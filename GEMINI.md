# AiQlick Jigasi - Gemini CLI Instructions

Custom Jitsi Jigasi fork for AWS Transcribe-based real-time transcription.

## Daily Commands
- `mvn compile` - Compile Java sources
- `mvn package` - Build the JAR archive

## Critical Rules
- **Transcription:** Configured to use `TranscribeService`.
- **WebSocket:** Connects to `wss://api.aiqlick.com/transcription/ws` (via background-tasks) for real-time speech-to-text.
- **Gating changes need a behavior diff + test:** diff what each audience could see/do before vs after against the base branch, and pin the must-stay-visible set in a test — a member allowlist once hid 44 of 56 tools its own comment claimed to allow (frontend PR #1161, 2026-09-06).

## Architectural Patterns
- **Maven:** Uses standard Maven lifecycle.
- **Service:** Operates as a hidden participant in Jitsi conferences to capture and stream audio.

For full details, see the root [GEMINI.md](../GEMINI.md) and [docs.aiqlick.com](https://docs.aiqlick.com).
- **Verify the deployed artifact is your code** before debugging a failing fix. Match deploy runs on `headSha`, not recency. Diagnose all layers in one pass; never `try/catch` the probe.

## Watching a long job (workspace rule)

Break a monitor on **process absence** (`pgrep -f '<script>' >/dev/null || break`),
never on a log marker — a job that dies a way you did not enumerate otherwise
polls forever, and silence is indistinguishable from progress. One watcher per
subject. Never pipe a long job through `| tail -N` (it buffers until exit, so a
hang looks like work — use `tee -a`). `kill -9` leaves a finalizer-dependent job,
such as a W&B run, showing `running`; send SIGTERM first. And never act
destructively on one early datapoint — read the trend.
