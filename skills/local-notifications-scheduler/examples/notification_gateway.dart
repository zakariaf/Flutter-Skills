// The narrow NotificationGateway port and its value objects, inlined here for one
// self-contained illustration. In the app tree they split: the pure value objects
// live in lib/core/notifications/scheduled_notification.dart and the abstract port
// in lib/services/notifications/notification_gateway.dart (which imports them).
// This file must NOT import flutter_local_notifications — only the FLN adapter may.
// `when` is always a Gregorian TZDateTime resolved in tz.local; `payload` is a
// serializable string that maps to a go_router location reconstructed from the DB.

import 'package:timezone/timezone.dart' as tz;

/// The disposable-cache view returned by the OS pending set.
class PendingNotification {
  final int id;
  const PendingNotification({required this.id});
}

/// Value object the pure ReminderScheduler emits. Immutable, with value equality
/// so tests can assert on the desired set directly.
class ScheduledNotification {
  final int id; // deterministic: hash(reminderId + occurrenceIndex + resolved `when`/content)
  // ^ fold `when` into the id: getPending() exposes only id, so an edited fire
  //   time must produce a NEW id or the reconcile skips it and fires the old time.
  final tz.TZDateTime when; // DST-correct fire instant, tz.local
  final String channelId; // e.g. due | overdue | info
  final String? groupId; // groupKey (Android) / threadIdentifier (iOS)
  final String payload; // serializable -> /reminders/:id

  const ScheduledNotification({
    required this.id,
    required this.when,
    required this.channelId,
    required this.payload,
    this.groupId,
  });

  @override
  bool operator ==(Object other) =>
      other is ScheduledNotification &&
      other.id == id &&
      other.when == when &&
      other.channelId == channelId &&
      other.groupId == groupId &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, when, channelId, groupId, payload);
}

/// The single abstraction all math and all tests talk to. Keep it to these four
/// operations — anything more belongs in the pure ReminderScheduler.
abstract class NotificationGateway {
  Future<void> schedule(ScheduledNotification n);
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<List<PendingNotification>> getPending();
}
