---
name: local-notifications-scheduler
description: >-
  Enforces an on-device reminder engine where the local database is the only source of
  truth and the OS pending-notification set is a disposable cache reconciled through one
  idempotent syncNotifications() entrypoint; keeps flutter_local_notifications behind a
  single NotificationGateway port, all scheduling math pure and Clock-injected, recurring
  schedules stored as wall-clock + recurrence rule (never UTC instants) and resolved to a
  TZDateTime in tz.local for DST correctness, inexact-alarm default with SCHEDULE_EXACT_ALARM
  as an opt-in, iOS ~64-cap budgeting, isolate-safe @pragma('vm:entry-point') tap handlers,
  and Android boot re-arm. Use when writing or editing notification_gateway.dart,
  fln_notification_gateway.dart, reminder_scheduler.dart, recurrence_rule.dart,
  syncNotifications, zonedSchedule wiring, snooze or mark-done re-anchoring, or diagnosing
  missed or wrong-hour notifications.
---

# Local Notifications Scheduler

One on-device reminder engine, owned centrally, with a narrow API. The local DB is the source of truth; the OS pending set is a disposable cache. Every scheduling change flows through one pure-then-reconcile path so the whole engine is verifiable off-device. Applies whenever you schedule, cancel, or reason about local notifications.

Read the reference for the task at hand:
- `references/notification-gateway-port.md` — the port contract, the two adapters, channels/grouping/deep-link payload rules.
- `references/scheduler-and-recurrence-rules.md` — pure `ReminderScheduler.compute` diff, recurrence/DST math, deterministic IDs, budgeting, the full test matrix.
- `references/platform-boot-exact-alarms-oem.md` — boot re-arm, exact-alarm degradation, background-isolate safety, Android manifest/Gradle, the OEM survival matrix.

Run `scripts/check-single-fln-import.sh`, `scripts/check-scheduler-purity.sh`, `scripts/check-adhoc-schedule-calls.sh`, and `scripts/check-manifest-permissions.sh` before a PR.

## Non-negotiable rules

1. **The local DB is the ONLY source of truth.** The OS pending-notification set is a disposable cache you reconcile against — never the store of record. Every reminder must be reconstructible from the DB alone after process death, reboot, Doze, or restore.
2. **Route EVERY scheduling change through one `syncNotifications()` reconcile entrypoint.** Never call `gateway.schedule()`/`cancel()` ad hoc from feature or UI code — that path cannot be made idempotent and desyncs the cache.
3. **Import `flutter_local_notifications` in exactly one file** — the FLN adapter. Everything else, including all tests, talks to the `NotificationGateway` port. A grep gate fails the build on any other import.
4. **Keep all scheduling math in pure, side-effect-free classes.** No plugin calls, no IO, no `DateTime.now()` inside them — inject a `Clock` from `package:clock`: Riverpod code reads it from `clockProvider`, the pure math takes it as a parameter (never `DateTime.now()`, never a bespoke `ClockService`). Purity is what makes off-device unit testing via `FakeNotificationGateway` possible.
5. **Store recurring schedules as wall-clock + recurrence rule, resolve to `TZDateTime` only at schedule time.** Never persist a recurring schedule as a UTC instant — it drifts an hour across every DST boundary. True one-off instants stay UTC epoch millis.
6. **Set `tz.local` at startup** (from `flutter_timezone`). The `timezone` package defaults to UTC — forget this and every `zonedSchedule` fires at the wrong local hour.
7. **Default to `AndroidScheduleMode.inexactAllowWhileIdle`** (permission-free, pierces Doze). Gate exact firing behind the user-revocable `SCHEDULE_EXACT_ALARM` via `canScheduleExactAlarms()` with silent fallback to inexact. **Never** declare `USE_EXACT_ALARM` — Play policy restricts it to alarm/timer/calendar apps and risks store rejection.
8. **Budget to ~50 pending on iOS** (headroom under the silent 64-cap). Sort future instants ascending, take the nearest ~50, refill on every foreground. The 65th+ silently never fires, with no error.
9. **Use deterministic IDs** derived from `reminderId + occurrenceIndex` **plus a hash of the resolved fire instant and notification content**. `getPending()` exposes only the `id`, not `when` — so if the id ignored the fire time, editing a reminder without changing its occurrence (a one-off moved 09:00→14:00, or a daily rule's hour changed) would keep the same id, be skipped by BOTH the cancel and schedule loops, and fire at the OLD time. Folding the resolved `TZDateTime` (and content) into the id makes an edit produce a NEW id — old id cancelled, new id scheduled. Unchanged input still maps to the same id, so reconcile stays a no-op.
10. **The app-foreground reconcile is the reliability backbone.** Boot receiver, background ticks, exact-alarm toggle, and OEM survival are all explicitly best-effort. With no server push there is no way to learn a reminder was dropped except the next foreground reconcile diff — that constraint is *why* this architecture exists, not a gap to paper over.

## Package / folder layout

The engine is shared infrastructure, not a feature — the pure math lives in `core/` (no Flutter, off-device testable) and the side-effect port + live impl + reconcile live in `services/`. `project-structure-and-packages` owns this tree.

```text
lib/
  core/
    notifications/                   # PURE — no Flutter, off-device testable
      reminder_scheduler.dart        # compute(desired) -> reconcile diff
      recurrence_rule.dart           # wall-clock + rule -> TZDateTime
      scheduled_notification.dart    # value objects (ScheduledNotification, PendingNotification)
      deterministic_id.dart          # reminderId + occurrence + resolved instant/content -> id
  services/
    notifications/                   # the side-effect port, live adapter, and reconcile
      notification_gateway.dart      # abstract PORT: schedule/cancel/cancelAll/getPending
      fln_notification_gateway.dart  # ONLY file importing flutter_local_notifications
      fake_notification_gateway.dart # in-memory list, for tests
      sync_notifications.dart        # the single reconcile entrypoint
      boot_rearm_android.dart        # BOOT_COMPLETED post-unlock re-arm
```

> **When multi-package (workspace):** promote the pure math + gateway into a `packages/notifications` package (where `lib/src/` + one public barrel is the sanctioned convention) so the ~N features that feed it cannot diverge. In a single-package app the `core/` + `services/` split is enough. See `project-structure-and-packages`.

Wire construction through Riverpod providers — never global singletons or per-feature instances. The `Clock` comes from `clockProvider` (`Clock.fixed(...)` in tests); see `service-boundary-and-native` for the throws-until-overridden port provider pattern.

## The canonical reconcile (the backbone)

`compute` is pure; the gateway diff is the only IO. This is the ONE entrypoint every scheduling change flows through.

```dart
Future<void> syncNotifications(
  NotificationGateway gw,
  Clock clock,
  ReminderRepository repo,
) async {
  final desired = ReminderScheduler.compute(     // PURE — no IO, injected clock
    reminders: await repo.activeReminders(),      // from the local DB (source of truth)
    now: clock.now(),
    budget: 50,                                   // headroom under the silent iOS 64-cap
  );                                              // sorts future instants ascending,
                                                  // takes the nearest ~50 as a rolling window
  final current = await gw.getPending();
  final desiredIds = {for (final d in desired) d.id};
  final currentIds = {for (final c in current) c.id};

  for (final c in current) {                      // cancel stale
    if (!desiredIds.contains(c.id)) await gw.cancel(c.id);
  }
  for (final d in desired) {                       // schedule new / changed
    if (!currentIds.contains(d.id)) await gw.schedule(d);
  }
}
```

Call `syncNotifications()` on: **app foreground/resume, reminder CRUD, backup import/restore, exact-alarm permission granted, Android boot, and the daily background tick.** See `examples/sync_notifications.dart` for the annotated version including the after-restore path.

## The gateway port

The port isolates the plugin so all scheduling math and all tests stay off-device.

```dart
abstract class NotificationGateway {
  Future<void> schedule(ScheduledNotification n);
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<List<PendingNotification>> getPending();
}
```

Keep it to exactly these four operations — anything more is a signal the logic belongs in the pure `ReminderScheduler`. The concrete `FlnNotificationGateway` is the single file importing `flutter_local_notifications`, `timezone`, and `flutter_timezone`; the `FakeNotificationGateway` is an in-memory `List`. Wire the concrete one through a Riverpod provider that tests override with the fake in a `ProviderContainer`. Full contract and the `ScheduledNotification` value object: `references/notification-gateway-port.md` and `examples/notification_gateway.dart`.

## Recurrence & DST

Resolve wall-clock + rule to a `TZDateTime` in `tz.local` at schedule time — DST-correct by construction.

```dart
// Wall-clock 9:00 daily -> concrete next fire instant, DST-safe.
tz.TZDateTime nextDailyAt(int hour, int minute, {required Clock clock}) {
  final now = tz.TZDateTime.from(clock.now(), tz.local);
  var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
  return next;
}
```

Genuinely calendar-recurring items may use one repeating notification (`matchDateTimeComponents`) consuming a single slot; everything else is a one-shot recomputed each reconcile. **Mark-done re-anchoring:** compute the next occurrence from the *actual* completion time, not the scheduled one, so recurring reminders don't drift. Never store "9am" as a UTC instant.

> Some apps derive a reminder time from a non-time trigger (e.g. "remind after N completions"). Keep that projection in a **pure, Clock-injected** helper that resolves to a concrete future instant *before* it reaches the scheduler, so the scheduler still handles one homogeneous list of instants. Debounce re-projection so a stream of inputs doesn't cause a reschedule storm.

## Background isolate & tap handling

The background tap/action handler needs `@pragma('vm:entry-point')` and runs in a **separate isolate with no main-isolate state**. Do **not** write to the DB from it — record a lightweight "pending action" intent (or nothing) and let the next foreground reconcile do the real work, avoiding concurrent DB access from two isolates. A tap maps a **serializable** payload → a `go_router` location reconstructed from the DB — never a non-serializable `extra`. See `async-safety` for `mounted`/context guards after the await, and `references/platform-boot-exact-alarms-oem.md`.

## Localization & backup

Notification titles/bodies are localized through gen-l10n with ICU plurals and numeral normalization; the schedule instant stays a Gregorian `TZDateTime` regardless of display calendar (see `i18n-rtl-l10n`). Backup does **not** carry OS notification state or exact-alarm grants — after import, run `cancelAll()` then a full reconcile; never assume restored pending IDs are valid.

## Anti-patterns

- **Calling `gateway.schedule()` from a feature/ViewModel.** Desyncs the cache and can't be made idempotent. Route through `syncNotifications()`.
- **Persisting a recurring schedule as a UTC instant.** Shifts the fire time by an hour across every DST boundary. Store wall-clock + rule.
- **`DateTime.now()` inside the scheduler.** Kills off-device testability. Inject a `Clock`.
- **Declaring `USE_EXACT_ALARM`** to "just make it fire on time." Play-policy rejection risk. Use the `SCHEDULE_EXACT_ALARM` opt-in with inexact fallback.
- **Scheduling an unbounded set.** iOS silently drops past 64. Budget and refill.
- **Writing to the DB from the tap isolate.** Concurrent access risks corruption. Record intent; reconcile on foreground.
- **Trusting a green emulator run for reboot/Doze/OEM survival.** Emulators lie. That confidence comes only from the real-device matrix.
- **Treating the OS pending set as the store of record.** It's a cache. The DB is truth.

## Definition of done

- [ ] `flutter_local_notifications` imported in exactly one file (`check-single-fln-import.sh` passes).
- [ ] Scheduler/recurrence math is pure and Clock-injected (`check-scheduler-purity.sh` passes).
- [ ] No ad-hoc `gateway.schedule/cancel` outside the reconcile (`check-adhoc-schedule-calls.sh` passes).
- [ ] `tz.local` set at startup before any `zonedSchedule`.
- [ ] Recurring schedules stored as wall-clock + rule; one-offs as UTC millis.
- [ ] `AndroidScheduleMode` chosen from `canScheduleExactAlarms()`; `USE_EXACT_ALARM` absent (`check-manifest-permissions.sh` passes).
- [ ] iOS budget ≤ ~50; nearest-ascending window; refill on foreground.
- [ ] Deterministic IDs fold in the resolved fire instant; uniqueness tested; reconcile idempotent on unchanged input AND reschedules on an edited fire time (old id cancelled, new id fires at the new time).
- [ ] Tap handler `@pragma('vm:entry-point')`, no DB write in the isolate, serializable payload → route.
- [ ] After-restore path: `cancelAll()` then full reconcile.
- [ ] Pure-Dart tests cover recurrence-across-DST, budget boundary, idempotent reconcile, restore-equals-desired.

## Related skills

- `service-boundary-and-native` — the injectable throws-until-overridden port provider and MethodChannel quarantine that the gateway follows.
- `naming-conventions` — the `[Concern]Gateway` suffix (a thin wrapper over a specific plugin, here `flutter_local_notifications`) vs `[Concern]Service`; owns the role-suffix table this skill follows.
- `persistence-drift` — the local DB that is the source of truth; scoped `.watch` streams that trigger reconciles.
- `async-safety` — `BuildContext`/`mounted` guards after `await` in tap handlers, subscription disposal.
- `state-management-riverpod` — providers-as-DI for the gateway and reconcile.
- `i18n-rtl-l10n` — localized bodies, ICU plurals, numeral normalization.
- `value-objects-money-and-units` — the injected `Clock` discipline shared here.
- `app-startup-and-bootstrap` — where `tz.local` and channel creation run before `runApp`.
- `testing-strategy` — fakes-over-mocks and clock-injected pure-core testing this engine relies on.

## References

- flutter_local_notifications: https://pub.dev/packages/flutter_local_notifications
- Zoned scheduling & timezones: https://pub.dev/packages/flutter_local_notifications#scheduling-a-notification
- timezone package: https://pub.dev/packages/timezone
- flutter_timezone: https://pub.dev/packages/flutter_timezone
- Android exact alarms: https://developer.android.com/develop/background-work/services/alarms/schedule
- Android USE_EXACT_ALARM policy: https://support.google.com/googleplay/android-developer/answer/13161072
- iOS UNUserNotificationCenter 64-notification limit: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- package:clock: https://pub.dev/packages/clock
