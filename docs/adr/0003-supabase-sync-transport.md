# 0003 — Sync the shared Clock over Supabase instead of CloudKit

Date: 2026-09-05. Supersedes the transport half of [0001](0001-shared-clock-over-cloudkit.md); the Clock model, last-action-wins rule, rollover and derived totals from 0001/0002 stand.

## Context

CloudKit needs the iCloud entitlement, which Apple only signs for paid Apple Developer Program teams. The project is signed by a personal team and the owner has decided not to pay Apple. Every Apple-hosted sync path (CloudKit, iCloud Drive, key-value store, push) sits behind the same entitlement.

The domain layer was built transport-agnostic: `ClockSnapshot`, `merged(local:remote:)`, the idempotent rollover, Session dedupe by `updatedAt`, and `TimerManager.adopt(_:notify:)` do not know where a remote state comes from.

## Decision

- Transport is a Supabase project (Postgres + Realtime + Auth), free tier: `https://wnwquybkpmyaufwkjmqw.supabase.co`.
- Identity is an Account: an email address and password, signed in once per device. Email confirmation is off on the project (editing the code email template requires custom SMTP, which is not worth it for one user). The SDK keeps the refresh token in the Keychain and renews silently, so sign-in is a setup step, not a habit.
- Two tables, both under row-level security keyed to the signed-in user and both in the Realtime publication:
  - `clock_state`: one row per Account, the Clock State columns plus `last_action_at` / `last_action_device`.
  - `sessions`: primary key (`user_id`, `date`), the Session columns plus `updated_at`. Sessions are identified by Study Day, matching the glossary; there is no separate id.
- Writes are optimistic and local-first. The app marks the Clock dirty and Sessions `needsUpload`, then flushes; failures retry. On sign-in, foreground, wake and reconnect the app does a full pull and reconciles: later `updated_at` wins per Session, a Session missing remotely is deleted locally unless it is still waiting to upload, and the Clock goes through the usual merge.
- The first device to sign in uploads everything it has; later devices merge rather than overwrite.
- Global reset deletes the Account's Sessions server-side; other devices receive the deletions live or on their next pull.
- CloudKit code, the `ClockState` SwiftData record, the iCloud/push entitlements and the `RT_CLOUDKIT` build switch are removed. One transport.

## Consequences

- No Apple entitlement is involved; personal-team builds sync.
- No push: the iPhone learns about a Mac action when the app is in the foreground (Realtime socket open) or on the next foreground pull. Same practical limit already accepted for the Live Activity. The Mac app runs all day and follows the phone within seconds.
- A free Supabase project pauses after about a week without traffic; daily use keeps it alive, and resuming is one click in the dashboard. Accepted.
- The publishable key ships inside the app. That is its purpose; row-level security is what protects the data.
- Both devices are assumed to share a time zone for the Study Day `date` column. The 4am boundary already assumes that.

## Rejected

- **Firebase**: equivalent shape, heavier SDK, no advantage.
- **Local-network sync (Multipeer)**: no server, but both devices must be awake on the same Wi-Fi; a locked phone would miss the Mac's actions.
- **A shared secret instead of accounts**: avoids email, but a leaked key is a leaked account with no way to rotate it per device.
