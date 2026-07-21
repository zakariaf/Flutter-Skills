// The single reconcile entrypoint. Every scheduling change flows through here:
// app foreground/resume, reminder CRUD, backup import/restore, exact-alarm granted,
// Android boot, and the daily background tick.
//
// `ReminderScheduler.compute` is PURE (no IO, no plugin, injected Clock).
// The gateway diff is the ONLY IO. The local DB is the source of truth; the OS
// pending set is a disposable cache we reconcile against.

import 'package:clock/clock.dart';

Future<void> syncNotifications(
  NotificationGateway gw,
  Clock clock,
  ReminderRepository repo,
) async {
  final desired = ReminderScheduler.compute(
    reminders: await repo.activeReminders(), // from the local DB
    now: clock.now(),
    budget: 50, // headroom under the silent iOS 64-cap; nearest ascending window
  );

  final current = await gw.getPending();
  final desiredIds = {for (final d in desired) d.id};
  final currentIds = {for (final c in current) c.id};

  // Cancel anything pending that is no longer desired.
  for (final c in current) {
    if (!desiredIds.contains(c.id)) {
      await gw.cancel(c.id);
    }
  }
  // Schedule anything desired that is not already pending. Deterministic IDs make
  // this idempotent: unchanged reminders map to the same id and are skipped. The
  // id folds in the resolved fire instant, so an edited time yields a new id —
  // the old id falls out of desired (cancelled above) and the new one schedules here.
  for (final d in desired) {
    if (!currentIds.contains(d.id)) {
      await gw.schedule(d);
    }
  }
}

// After backup/restore, OS notification state and exact-alarm grants do NOT
// survive. cancelAll() first, then a full reconcile — never trust restored IDs.
Future<void> reconcileAfterRestore(
  NotificationGateway gw,
  Clock clock,
  ReminderRepository repo,
) async {
  await gw.cancelAll();
  await syncNotifications(gw, clock, repo);
}
