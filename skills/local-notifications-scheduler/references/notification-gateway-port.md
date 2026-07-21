# NotificationGateway port

The port isolates the plugin so all scheduling math and all tests stay off-device. The FLN adapter is the **only** class that imports `flutter_local_notifications`; everything else — including every test — talks to this abstraction.

## The port

```dart
abstract class NotificationGateway {
  Future<void> schedule(ScheduledNotification n);
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<List<PendingNotification>> getPending();
}
```

- Keep it narrow: exactly these four operations. Any scheduling logic that reaches for more is a signal the logic belongs in the pure `ReminderScheduler` instead.
- Wire the concrete gateway through a Riverpod provider so tests override it with `FakeNotificationGateway` in a `ProviderContainer`. The provider should throw until overridden at the composition root (see `service-boundary-and-native`).

## `ScheduledNotification` value object

Carries `id` (deterministic), `when` (Gregorian `TZDateTime` in `tz.local`), `channelId`, an optional `groupId`, and a **serializable** `payload`. The payload maps to a `go_router` location reconstructed from the local DB on tap — never a non-serializable `extra`. Keep it an immutable value type with value equality so tests can assert on the desired set directly.

## Real adapter — `FlnNotificationGateway`

- The single file that imports `flutter_local_notifications`, `timezone`, and `flutter_timezone`. `scripts/check-single-fln-import.sh` enforces this.
- Set `tz.local` from `flutter_timezone` at startup, before any `zonedSchedule` call.
- Use `zonedSchedule` on both platforms. Pick `AndroidScheduleMode` from `canScheduleExactAlarms()` (see `platform-boot-exact-alarms-oem.md`).
- Create channels up front (immutable sound/vibration/importance) and set `groupKey` (Android) / `threadIdentifier` (iOS) from `groupId`.
- `getPending()` maps `pendingNotificationRequests()` to the port's `PendingNotification` list — the disposable cache the reconcile diffs against.

```dart
await plugin.zonedSchedule(
  n.id,
  title,          // localized at render, from gen-l10n
  body,
  n.when,         // tz.TZDateTime in tz.local
  NotificationDetails(
    android: AndroidNotificationDetails(n.channelId, channelName, groupKey: n.groupId),
    iOS: DarwinNotificationDetails(threadIdentifier: n.groupId),
  ),
  androidScheduleMode: mode, // exact vs inexact from canScheduleExactAlarms()
  payload: n.payload,        // serializable -> route
);
```

## Fake adapter — `FakeNotificationGateway`

- In-memory `List<ScheduledNotification>` implementing the port. `schedule` upserts by id, `cancel` removes by id, `cancelAll` clears, `getPending` returns the ids.
- No plugin, no platform channel, no `TZDateTime` resolution needed beyond what the test injects. Drives every reconcile/idempotency/budgeting/restore test deterministically. See `examples/fake_notification_gateway.dart`.

## Channels, grouping, actions

- Create channels up front **by urgency** (e.g. `due`, `overdue`, `info`) — never per-item. **Sound/vibration/importance is immutable after first creation** — version the channel ID if behavior must change.
- **Group related items** with a stable `groupId` plus a group-summary on Android; collapse a busy period's items into one digest instead of many buzzes. Honor quiet hours (local time) and a preferred delivery time if the app has them.
- Notification actions ("Done", "Snooze") should resolve without opening the app where possible; each action re-anchors the next occurrence to the actual action time and triggers a reconcile.
- iOS `UNTimeIntervalNotificationTrigger` must be ≥ 60 s — prefer concrete one-shot `zonedSchedule` for projected reminders.

## The reconcile contract

`syncNotifications()` is the ONLY caller of `schedule`/`cancel` in production. It:

1. computes the desired set with the pure `ReminderScheduler.compute` (budget ~50),
2. reads `getPending()`,
3. cancels pending IDs not in desired,
4. schedules desired IDs not already pending.

Because IDs are deterministic, an unchanged reminder set produces a no-op. After backup/restore, call `cancelAll()` first (OS state and exact-alarm grants do not survive import), then reconcile.

## CI enforcement

- Single-import grep (`scripts/check-single-fln-import.sh`): fail on any `flutter_local_notifications` import outside the adapter.
- Purity grep (`scripts/check-scheduler-purity.sh`): fail on `DateTime.now()` / plugin imports / IO inside the scheduler or recurrence math.
- Ad-hoc-call grep (`scripts/check-adhoc-schedule-calls.sh`): fail on `gateway.schedule(`/`cancel(` calls outside the reconcile entrypoint.
