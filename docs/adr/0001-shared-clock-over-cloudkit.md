---
status: accepted
date: 2026-09-05
---

# One shared Clock synced over CloudKit with last-action-wins

The app is gaining a Mac version and the user wants the timer state shared across devices. We decided there is exactly one Clock per Apple ID rather than one Clock per device, and that its state is synced through CloudKit (via SwiftData) rather than a custom backend. When two devices act on the Clock without seeing each other, the Clock Action with the later timestamp wins outright; every action banks the elapsed time before it writes, so a losing action never discards minutes already counted. The same rule resolves duplicate Sessions for one Study Day and conflicting Manual Edits.

## Considered options

- **Per-device Clocks with merged history.** Rejected: two devices running at once would double-count the same minutes, and no overlap rule for a study timer is intuitive.
- **Supabase or another custom backend.** Rejected: real-time sync would be easy, but it adds an auth flow, a schema, and hosting to a personal Apple-only app. Revisit only if a non-Apple client is ever wanted.
- **iCloud Key-Value Store.** Rejected: can lag by minutes, which breaks "I paused on my phone, the Mac should stop now".
- **Prompting the user on conflict, or longest-run-wins.** Rejected: prompts violate the app's silence principle, and longest-run-wins rewards a Clock accidentally left running overnight.

## Consequences

- The 4am Rollover must be idempotent: whichever device first sees a stale Study Day performs it and writes the new Study Day into the Clock State; others skip.
- Resets are global. Reset Total deletes every Session everywhere; the second confirmation must say so.
- CloudKit cannot send ActivityKit push-to-start, so a Clock started from the Mac does not summon the iPhone Live Activity until the phone app is next opened.
- CloudKit requires the paid Apple Developer Program.
