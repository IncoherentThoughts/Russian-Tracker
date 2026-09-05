# Russian Tracker — Domain Glossary

The language of the project. Terms here are canonical; code and docs should use them.

## Clock
The single running stopwatch. Exactly one Clock exists per user, shared across every device signed into the same account. Any device can start, pause, or switch the Clock's Study Type, and all devices show the same state. Starting a Clock that is already running is a no-op.

## Clock State
Everything needed to reproduce the Clock on any device: whether it is running, when the current run began, the active Study Type, and the seconds already banked for the current Study Day (overall and per Study Type).

## Clock Action
A timestamped change to the Clock State made on one device: start, pause, switch Study Type, or Rollover. When two devices act without seeing each other, the later Clock Action wins outright. Every Clock Action banks the time elapsed before it, so a losing action never loses minutes already counted.

## Study Day
The unit the daily timer counts. Runs from 4:00 AM to 4:00 AM local time, not midnight. A Study Day is named by the calendar date it began on.

## Rollover
The transition from one Study Day to the next at 4:00 AM. The departing Study Day's time becomes a Session; the daily counters start again at zero. A running Clock keeps running across a Rollover.

## Session
The record of one Study Day: its date, total seconds, and the split across Study Types. There is at most one Session per Study Day. Sessions are the history that Stats reads.

## Study Type
The kind of study the Clock is currently crediting: Grammar, Immersion, or Anki. The Clock is unaffected by the type; the type only decides which bucket its seconds land in. Switching type mid-run splits the run at that instant.

## Daily Goal
The target number of hours per Study Day, set by the user. Drives the progress bar in the Live Activity, the Mac menu bar popover, and the widget. Default four hours.

## All-Time Total
The sum of every Session's total plus the current Study Day's time. Never stored as its own number; always derived. The same holds for each Study Type's all-time figure.

## Manual Edit
A user-entered override of a Session's total for a given date. Raises or lowers the day's total without attributing the difference to any Study Type.

## Live Activity
The iOS Lock Screen and Dynamic Island presentation of the Clock. Its Mac counterparts are the Menu Bar Item, the Menu Bar Popover, and the Widget.

## Menu Bar Item
The Mac status-bar element. Shows the app icon, plus today's ticking elapsed time only while the Clock is running.

## Menu Bar Popover
The panel opened by clicking the Menu Bar Item: today's time, all-time total, Start/Pause, the Study Type switcher, the Daily Goal bar, and a link to open the full window.

## Widget
The Mac Notification Center widget (small and medium). Interactive: Start/Pause and Study Type switching without opening the app.

**Account**
The email identity that owns one shared Clock and its Sessions. Every device signs into the same Account once (email and password); sync happens between devices on the same Account.
