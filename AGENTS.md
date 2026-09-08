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
- **Never gate visibility with an untested filter — in either direction.** A member tool allowlist commented "everything except admin-only writes" was a closed 12-item list hiding 44 of 56 sidebar tools (frontend PR #1161, 2026-09-06; proven by counting `value:` in `git show 64e663ba~1:components/reusable/chatbot/ChatPanel.tsx:76-153` = 56 against the 12-item set). When you add or tighten any audience/role gating: diff what each audience could see or do before vs after against the base branch, and pin the must-stay-visible set with a test that names names. Comments assert; only the diff and the test prove.

## Watching a long job (workspace rule)

Break a monitor on **process absence** (`pgrep -f '<script>' >/dev/null || break`),
never on a log marker — a job that dies a way you did not enumerate otherwise
polls forever, and silence is indistinguishable from progress. One watcher per
subject. Never pipe a long job through `| tail -N` (it buffers until exit, so a
hang looks like work — use `tee -a`). `kill -9` leaves a finalizer-dependent job,
such as a W&B run, showing `running`; send SIGTERM first. And never act
destructively on one early datapoint — read the trend.

## CI completion and smoke-test evidence

- Match deployment and CI/security runs to the exact commit separately. A successful deployment does not make queued checks green. Inspect `gh api repos/<owner>/<repo>/actions/runs/<id>/jobs`: a run can remain `queued` while individual jobs are running or already successful. Check eligible runner labels and busy state before restarting runners or changing workflows.
- Cancel an obsolete promotion-PR run only after confirming the PR is merged and equivalent checks remain on the intended commit. Preserve the actual production checks and unrelated work; never cancel a unique security gate to finish faster.
- A short-lived probe can exit before an attached client captures stdout. Empty output is inconclusive, not proof of an HTTP/auth failure. Wait for container termination, read persisted logs and its exit code, and enforce the expected status AND body size. Keep transport failures distinct and fail closed.
- Read the failed step before retrying. A wall-clock threshold can be affected by runner contention; one unchanged rerun of the failed job can establish whether it repeats. A passing retry does not prove every timing failure harmless. Investigate recurring failures without widening thresholds, skipping assertions, or suppressing scanner findings.

Verified 2026-09-08: backend CI run `34210498184` progressed at job level while queued; docs run `34211487120` enforced `302 0` from completed-pod logs; backend dev run `34209852994` passed its failed timing shard unchanged on attempt 2.
