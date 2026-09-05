---
status: accepted
date: 2026-09-05
---

# All-time totals are derived from Sessions, never stored

The timer previously kept running counters for the all-time total and for each Study Type's all-time figure in the shared UserDefaults suite. With a shared Clock across devices, two devices adding seconds to the same counter while offline would double-count on merge. We decided the All-Time Total is always the sum of every Session's total plus the current Study Day's time, and each Study Type's all-time figure is the sum of that type across Sessions plus today. Nothing extra syncs and the two can never disagree.

## Consequences

- Reset Total is now just "delete every Session and zero today"; it already deleted Sessions before, so behaviour is unchanged.
- A Manual Edit of a past day moves the total by exactly the size of the edit, as it did before.
- The Live Activity, Mac popover, and widget read today's time from the Clock State and the total from a cached sum the app refreshes after every sync; the intents never need to touch a total counter.
- The `totalElapsed` and `total_<type>` UserDefaults keys are retired. The earlier one-off recalibration migration becomes unnecessary and is removed.
