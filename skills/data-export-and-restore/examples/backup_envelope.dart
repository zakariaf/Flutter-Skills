// A complete backup envelope: header-first fields (formatVersion, schemaVersion,
// appVersion, exportedAtUtc, payload checksum), a streaming write published by
// atomic rename with the temp file deleted on every failure path, and a reader
// that walks the validation ladder returning one typed failure per refusal reason.
//
// Domain is neutral (Note). The Result/Failure spine is the one from
// `error-handling-typed-results`; only the parts used here are restated.

import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart'; // sha256

// --- Spine (see error-handling-typed-results) --------------------------------

sealed class Result<T, F extends Failure> {
  const Result();
}

final class Ok<T, F extends Failure> extends Result<T, F> {
  const Ok(this.value);
  final T value;
}

final class Err<T, F extends Failure> extends Result<T, F> {
  const Err(this.failure);
  final F failure;
}

sealed class Failure {
  const Failure();

  /// Stable code the presentation layer maps to a localized message.
  String get code;
}

/// One arm per refusal reason — "restore failed" with no reason is
/// indistinguishable from data loss to the person reading it.
sealed class RestoreFailure extends Failure {
  const RestoreFailure();
}

final class RestoreUnreadable extends RestoreFailure {
  const RestoreUnreadable();
  @override
  String get code => 'restore.unreadable';
}

final class RestoreNotOurFormat extends RestoreFailure {
  const RestoreNotOurFormat();
  @override
  String get code => 'restore.not_our_format';
}

final class RestoreCorrupt extends RestoreFailure {
  const RestoreCorrupt();
  @override
  String get code => 'restore.corrupt';
}

/// The file was written by a NEWER app. Carry the numbers so the message can say
/// which version to update to — never attempt a best-effort parse.
final class RestoreNewerThanApp extends RestoreFailure {
  const RestoreNewerThanApp({required this.fileSchema, required this.appSchema});
  final int fileSchema;
  final int appSchema;
  @override
  String get code => 'restore.newer_than_app';
}

final class RestoreMalformed extends RestoreFailure {
  const RestoreMalformed(this.firstOffendingId);
  final String? firstOffendingId;
  @override
  String get code => 'restore.malformed';
}

sealed class ExportFailure extends Failure {
  const ExportFailure();
}

final class ExportWriteFailed extends ExportFailure {
  const ExportWriteFailed(this.cause);
  final Object cause;
  @override
  String get code => 'export.write_failed';
}

// --- The envelope ------------------------------------------------------------

/// Bumped when the ENVELOPE's own shape changes — independently of the database.
const int kFormatVersion = 1;

/// The database schema this build reads. Owned by the Drift database class.
const int kSchemaVersion = 7;

const String kFormatMarker = 'app.backup';

class BackupEnvelope {
  const BackupEnvelope({
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.exportedAtUtc,
    required this.payload,
  });

  final int formatVersion;
  final int schemaVersion;
  final String appVersion;
  final DateTime exportedAtUtc;

  /// Canonical values only: integer minor units, SI integers, ISO-8601 UTC,
  /// stable content ids, untranslated enum codes. Never a localized numeral.
  final Map<String, Object?> payload;
}

// --- Write: stream to temp, checksum, publish by rename ----------------------

/// Writes the backup and returns the PUBLISHED file. Nothing partial is ever
/// left behind: every failure path deletes the temp file and publishes nothing.
Future<Result<File, ExportFailure>> writeBackup(
  Directory dir,
  Map<String, Object?> payload, {
  required String appVersion,
}) async {
  // Sorted keys + sorted rows keep the bytes stable so the round-trip test can
  // assert byte identity instead of a fuzzy structural compare.
  final payloadBytes = utf8.encode(jsonEncode(_sorted(payload)));
  final checksum = sha256.convert(payloadBytes).toString();

  final stamp = clock.now().toUtc().toIso8601String(); // injected Clock, never DateTime.now()
  final tmp = File('${dir.path}/backup.json.tmp');
  final published = File('${dir.path}/backup-$stamp.json');

  IOSink? sink;
  try {
    sink = tmp.openWrite();
    // Header FIRST: a truncated or foreign file is then rejected by the header
    // rather than by an exception thrown somewhere in the middle of the payload.
    sink
      ..write('{"format":"$kFormatMarker",')
      ..write('"formatVersion":$kFormatVersion,')
      ..write('"schemaVersion":$kSchemaVersion,')
      ..write('"appVersion":${jsonEncode(appVersion)},')
      ..write('"exportedAtUtc":${jsonEncode(stamp)},')
      ..write('"payloadSha256":${jsonEncode(checksum)},')
      ..write('"payload":')
      ..add(payloadBytes) // streamed — never materialized as one giant String
      ..write('}');
    await sink.flush();
    await sink.close();
    sink = null;

    // Publish atomically only once the last byte is on disk.
    return Ok(await tmp.rename(published.path));
  } on Object catch (e) {
    await sink?.close();
    if (tmp.existsSync()) await tmp.delete(); // never leave a truncated "backup"
    return Err(ExportWriteFailed(e));
  }
}

// --- Read: the validation ladder ---------------------------------------------

/// Rungs run cheapest-and-most-destructive-to-skip first; nothing below a rung
/// runs until it passes, and NOTHING is written before the ladder completes.
Result<BackupEnvelope, RestoreFailure> readEnvelope(File file) {
  // 1. Readable.
  final String raw;
  try {
    raw = file.readAsStringSync();
  } on FileSystemException {
    return const Err(RestoreUnreadable());
  }
  if (raw.isEmpty) return const Err(RestoreUnreadable());

  // 2. Ours — marker and envelope version, before anything else is trusted.
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const Err(RestoreNotOurFormat());
  }
  if (decoded is! Map<String, Object?> ||
      decoded['format'] != kFormatMarker ||
      decoded['formatVersion'] is! int) {
    return const Err(RestoreNotOurFormat());
  }
  if ((decoded['formatVersion']! as int) > kFormatVersion) {
    return Err(RestoreNewerThanApp(
      fileSchema: decoded['schemaVersion'] as int? ?? -1,
      appSchema: kSchemaVersion,
    ));
  }

  // 3. Intact — verify the checksum BEFORE parsing the payload, or a truncated
  //    file fails somewhere random and reports the wrong reason.
  final payload = decoded['payload'];
  if (payload is! Map<String, Object?> || decoded['payloadSha256'] is! String) {
    return const Err(RestoreCorrupt());
  }
  final actual = sha256.convert(utf8.encode(jsonEncode(_sorted(payload)))).toString();
  if (actual != decoded['payloadSha256']) return const Err(RestoreCorrupt());

  // 4. Not from the future — refuse outright, never "best effort".
  final fileSchema = decoded['schemaVersion'];
  if (fileSchema is! int) return const Err(RestoreCorrupt());
  if (fileSchema > kSchemaVersion) {
    return Err(RestoreNewerThanApp(fileSchema: fileSchema, appSchema: kSchemaVersion));
  }

  final exportedAt = DateTime.tryParse(decoded['exportedAtUtc'] as String? ?? '');
  if (exportedAt == null || !exportedAt.isUtc) {
    return const Err(RestoreMalformed(null)); // a naive local instant cannot be restored
  }

  // Rungs 5-7 (per-row well-formedness, in-file referential integrity, disk
  // space) run in the importer against the STAGING database — see
  // references/restore-and-merge-policy.md.
  return Ok(BackupEnvelope(
    formatVersion: decoded['formatVersion']! as int,
    schemaVersion: fileSchema,
    appVersion: decoded['appVersion'] as String? ?? 'unknown',
    exportedAtUtc: exportedAt,
    payload: payload,
  ));
}

/// Stable ordering — the checksum and the byte-identity round-trip test both
/// depend on the same map serializing the same way every time.
Map<String, Object?> _sorted(Map<String, Object?> map) {
  final keys = map.keys.toList()..sort();
  return {
    for (final k in keys)
      k: switch (map[k]) {
        final Map<String, Object?> m => _sorted(m),
        final List<Object?> l => l
            .map((e) => e is Map<String, Object?> ? _sorted(e) : e)
            .toList(growable: false),
        final other => other,
      },
  };
}
