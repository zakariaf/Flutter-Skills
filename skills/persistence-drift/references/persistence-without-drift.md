# Persistence without Drift — plain JSON files

Not every app needs SQLite. When the data is a small library of independent
records with no relational queries — a handful of documents, a settings blob, a
roster — a directory of JSON files is simpler and honest. The **discipline is the
same** as the Drift path: injected base dir, a single store type, atomic durable
writes, lenient decode, and no data loss on background/lock. Reach for Drift when
you need relations, indexed queries, transactions across records, or reactive
`.watch` streams; reach for files when you do not.

## The store type

Hide all I/O behind one injectable store so the rest of the app never touches the
filesystem and tests run against a temp dir.

```dart
/// One file per record + a small index/settings file. Base dir injected for tests.
class NoteStore {
  NoteStore(this.baseDir); // Application Support in prod, a temp dir in tests.
  final Directory baseDir;

  Future<List<Note>> loadAll();          // read every notes/*.json, newest first, skip corrupt
  Future<void> save(Note note);          // notes/<id>.json, atomic
  Future<void> delete(String id);        // remove one file
  Future<Settings> loadSettings();       // settings.json
  Future<void> saveSettings(Settings s);
}
```

## Rules

- **Location: Application Support, not Documents.** Documents is user-visible and
  iCloud-exposed; an internal store belongs in Application Support. Create the
  directory with intermediates on first launch.
- **One file per record.** Only the edited record's file rewrites; a settings/
  roster file saves on its own changes. A corrupt or missing file is skipped, not
  fatal — never let one bad record fail the whole load.
- **Atomic writes.** Write to a temp file and rename, or use the platform's atomic
  option, so a crash mid-write never truncates the live file. Keep the **default**
  file-protection class — a stricter "complete protection" class makes a save
  firing exactly at screen-lock *fail*, which is the loss case you most need to
  survive.
- **Debounce writes (~hundreds of ms) AND flush on lifecycle change.** A
  cancel-and-reschedule debounce batches rapid edits; a lifecycle listener
  (`AppLifecycleState.inactive`/`paused`) flushes immediately as belt-and-braces
  against background/kill. Snapshot the immutable value and write off the UI
  thread.
- **Decode leniently, per field.** Use `?? default` for each field so an
  old-shape record loads without version branches — no schema-version machinery
  for a flat file store. (If shape drift becomes real and relational, that is the
  signal to move to Drift.)
- **Clear/delete cancels the pending debounced write** for that record first, so
  no stray in-flight save resurrects a just-deleted file.

## The same invariants still apply

- Store **canonical values** (integer minor units, UTC instants, serial local
  day) — the file is a serialization boundary, not a display format.
- Keep **derived state out** of the file; recompute on load.
- The store returns **immutable value objects**; the JSON shape is a store secret,
  never passed to widgets.
- Inject the base dir so every path in a test points at a temp directory — the
  file equivalent of `NativeDatabase.memory()`.
