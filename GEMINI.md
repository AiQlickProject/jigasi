# AiQlick Jigasi - Gemini CLI Instructions

Custom Jitsi Jigasi fork for AWS Transcribe-based real-time transcription.

## Daily Commands
- `mvn compile` - Compile Java sources
- `mvn package` - Build the JAR archive

## Critical Rules
- **Transcription:** Configured to use `TranscribeService`.
- **WebSocket:** Connects to `wss://api.aiqlick.com/transcription/ws` (via background-tasks) for real-time speech-to-text.

## Architectural Patterns
- **Maven:** Uses standard Maven lifecycle.
- **Service:** Operates as a hidden participant in Jitsi conferences to capture and stream audio.

For full details, see the root [GEMINI.md](../GEMINI.md) and [docs.aiqlick.com](https://docs.aiqlick.com).
