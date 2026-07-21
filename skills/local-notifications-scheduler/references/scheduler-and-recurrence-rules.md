# Scheduler & recurrence rules

Detailed rules for the pure scheduling core — `ReminderScheduler`, recurrence resolution, deterministic IDs, and the optional clock-tamper guard. Everything here is unit-testable off-device with an injected `Clock` and `FakeNotificationGateway`.

## Why exactly one testable owner

There is ONE scheduler for the whole app. A per-feature scheduler would diverge, duplicate the iOS-cap logic, and make the reconcile impossible to reason about. Keep the math pure and the plugin behind a port so the whole engine is verifiable without a device.

## `ReminderScheduler.compute` — pure diff producer

- Input: active reminders (from the local DB), `now`, `budget`. Output: the desired `List<ScheduledNotification>`. No IO, no plugin, no `DateTime.now()`.
- **iOS 64-cap budgeting:** sort all future instants **ascending**, take the nearest `budget` (~50, headroom under 64). Calendar-recurring items may use ONE repeating notification (`matchDateTimeComponents`) consuming a single slot; other reminders are one-shots. Refill on every foreground.
- **Idempotent:** identical inputs → identical output → reconcile is a no-op. A changed input yields a targeted cancel/add diff only.
- **Mark-done re-anchoring:** when a reminder is completed, compute the next occurrence from the *actual* completion time, not the scheduled one, so recurring reminders don't drift.
- **Overdue:** if a reminder's target instant is already in the past at compute time, emit an immediate "overdue" notification and drop the stale pending one.

## Wall-clock vs UTC storage

- **True one-off instants** (a timestamp captured from an event): store as UTC epoch millis.
- **Recurring schedules:** store wall-clock hour/minute + recurrence rule. Resolve to `TZDateTime(tz.local, y, m, d, hour, minute)` only at (re)schedule time. Storing a recurring schedule as UTC shifts "9am" by an hour across DST — banned.
- A date-only reminder must NOT shift off its intended day on a DST or manual clock change — anchor it to wall-clock local midnight, not a UTC instant.

## Recurrence resolution

```dart
// Next fire instant for a wall-clock daily rule, DST-safe.
tz.TZDateTime nextDailyAt(int hour, int minute, {required Clock clock}) {
  final now = tz.TZDateTime.from(clock.now(), tz.local);
  var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
  return next;
}
```

- Weekly/monthly rules walk forward the same way from the current wall-clock instant.
- The DST edge cases that matter: on the "spring forward" gap, a 2:30 local time may not exist — resolve to the next valid instant. On "fall back", a wall-clock time occurs twice — pick the first. `TZDateTime` normalizes these; assert them in tests against a known non-UTC zone.

## Deterministic IDs

- ID = deterministic 32-bit hash of `reminderId + occurrenceIndex + the resolved fire instant` (and any content that affects the notification, e.g. title/body key).
- **Why the fire instant MUST be in the id:** `getPending()` exposes only `id`, not `when`. If the id were `reminderId + occurrenceIndex` alone, editing a reminder's time *without* changing the occurrence — a one-off moved 09:00→14:00, or a daily rule's hour changed — would leave the id unchanged. The cancel loop skips it (still in desired) and the schedule loop skips it (already pending), so the OS keeps firing the OLD time — the exact wrong-hour bug this engine promises to prevent. Folding the resolved `TZDateTime` into the id makes an edit yield a NEW id: the old id drops out of desired (cancelled) and the new id is scheduled at the new time. (A stable-id-only design cannot detect in-place edits; it would instead have to cancel+reschedule the whole affected `reminderId` on every CRUD edit.)
- **Reserve an ID range per feature/module** so cross-module hashing cannot collide silently. Test uniqueness across all sources in a single exhaustive test.
- Same input → same id keeps reconcile idempotent (a no-op); a changed fire instant or content → new id gives the targeted cancel/add diff, so `getPending()` diffing detects edits despite exposing only the id.

## Clock-tamper guard (optional, for overdue-sensitive apps)

- Overdue detection can use a **monotonic clock guard** (not just wall-clock) so a user winding the device clock forward/back cannot spuriously mark reminders overdue or suppress genuine ones.
- Store the last-seen monotonic + wall-clock pair; a wall-clock jump the monotonic clock does not corroborate is treated as tampering and does not trigger overdue transitions. Skip this if your reminders are not penalty-bearing.

## Test matrix (pure-Dart, no device)

| Area | Cases |
| --- | --- |
| `ReminderScheduler` | nearest-N window at the iOS-64 boundary; idempotent no-op; correct cancel/add diff; **editing a reminder's fire time reschedules it (old id cancelled, new id fires at the new time)**; overdue on a past-target reminder; deterministic-ID uniqueness across modules |
| Recurrence/DST | schedule across spring-forward and fall-back boundaries in a non-UTC device tz; assert correct wall-clock fire time; leap-day and short-month rules |
| Re-anchoring | mark-done recomputes next occurrence from actual completion time |
| Restore/import | after import, `cancelAll()` + full reconcile equals exactly the desired set, no stale IDs |
| Localization | title/body render with correct plurals, numerals, and bidi isolation for embedded technical strings |

Integration (`integration_test` + a device/emulator, CI-runnable but not a survival proof): after a reconcile, `pendingNotificationRequests()` equals the desired set; short-fuse delivery smoke; `adb reboot` then assert still pending; Doze via `adb shell dumpsys deviceidle force-idle`; exact-alarm revocation → silent inexact fallback; enqueue 70 → only ~50 nearest survive.
