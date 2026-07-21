// In-memory implementation of the NotificationGateway port. Drives every
// reconcile / idempotency / iOS-budgeting / restore test deterministically —
// no plugin, no platform channel, no device.

class FakeNotificationGateway implements NotificationGateway {
  final List<ScheduledNotification> scheduled = [];

  @override
  Future<void> schedule(ScheduledNotification n) async {
    scheduled.removeWhere((e) => e.id == n.id); // upsert by deterministic id
    scheduled.add(n);
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }

  @override
  Future<List<PendingNotification>> getPending() async {
    return [
      for (final n in scheduled) PendingNotification(id: n.id),
    ];
  }
}

// Example test skeletons (package:test + package:clock):
//
//   test('reconcile is a no-op when nothing changed', () async {
//     final gw = FakeNotificationGateway();
//     final clock = Clock.fixed(DateTime.utc(2026, 1, 1));
//     await syncNotifications(gw, clock, repo);
//     final firstIds = (await gw.getPending()).map((p) => p.id).toSet();
//     await syncNotifications(gw, clock, repo); // second pass, same inputs
//     expect((await gw.getPending()).map((p) => p.id).toSet(), firstIds);
//   });
//
//   test('enqueue 70 -> only nearest ~50 survive the budget', () async { /* ... */ });
//   test('recurrence across DST fires at the correct wall-clock hour', () async { /* ... */ });
//   test('after restore, cancelAll + reconcile equals exactly the desired set',
//       () async { /* ... */ });
