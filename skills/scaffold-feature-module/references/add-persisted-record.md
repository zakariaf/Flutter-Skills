# Optional: add a persisted record the feature reads

When a screen needs a record that does not exist yet, add the store chain **before** wiring the
feature, so the feature can read its scoped `.watch()` stream. This is a bridge only — the full ritual
(schema invariants, transactions, migrations, tests) lives in `persistence-drift` and `run-migration`.

## The chain — one link per layer

```
value type (pure)  →  Drift table (schema invariants)  →  DAO (rows→value type)  →  repository (one txn)
```

1. **Immutable value type — pure, no store import.** `final` fields, a `const` constructor, value
   equality, `copyWith`. Imports `dart:core` / `package:meta` only; a `package:drift` or
   `package:flutter` import here is a compile error, not a style nit. Closed sets are enums so invalid
   states are unrepresentable; names carry units; a calendar day is a date type, an instant is a UTC
   `DateTime` named as one.

   ```dart
   // domain/task.dart — the bottom of the graph.
   enum TaskStatus { open, done, archived }

   @immutable
   class Task {
     const Task({
       required this.id,
       required this.projectId,
       required this.title,
       required this.status,
       required this.createdAtUtc,   // UTC instant, named as one
     });
     final String id;
     final String projectId;
     final String title;
     final TaskStatus status;
     final DateTime createdAtUtc;

     Task copyWith({String? title, TaskStatus? status}) => Task(
           id: id, projectId: projectId,
           title: title ?? this.title, status: status ?? this.status,
           createdAtUtc: createdAtUtc,
         );
   }
   ```

2. **Drift table — invariants in the SCHEMA, confined to the data layer.** `STRICT` typing,
   `CHECK (... IN (...))` mirroring each enum, range checks, foreign keys with `ON DELETE CASCADE`
   where a parent owns the row, and query indices — enforced by SQLite, not application code. Add the
   table to `@DriftDatabase(tables: [...])`. `package:drift` appears **only** here and in the DAO.

   ```dart
   class Tasks extends Table {
     TextColumn get id => text()();
     TextColumn get projectId => text().references(Projects, #id, onDelete: KeyAction.cascade)();
     TextColumn get title => text().withLength(min: 1)();
     TextColumn get status =>
         text().check(status.isIn(const ['open', 'done', 'archived']))();
     TextColumn get createdAt => text()();   // UTC ISO-8601 instant
     @override
     Set<Column> get primaryKey => {id};
     @override
     bool get isStrict => true;
   }
   // Migration adds: INDEX ix_tasks_by_project ON tasks(project_id, created_at).
   ```

3. **DAO — the only door to SQL; maps rows to the value type.** No Drift `Table`/`Companion`/row
   class ever crosses the data-layer boundary. The reactive read is a scoped `.watch()`.

   ```dart
   @DriftAccessor(tables: [Tasks])
   class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
     TasksDao(super.db);

     Stream<List<Task>> watchTasks(String projectId) =>
         (select(tasks)
               ..where((t) => t.projectId.equals(projectId))
               ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
             .watch()
             .map((rows) => rows.map(_toModel).toList());

     Task _toModel(TaskRow r) => Task(
           id: r.id, projectId: r.projectId, title: r.title,
           status: TaskStatus.values.byName(r.status),
           createdAtUtc: DateTime.parse(r.createdAt),
         );
   }
   ```

4. **Repository — one transaction per mutation, persist-before-publish.** The single write path the
   feature calls. Every query inside the transaction is `await`-ed; the ViewModel republishes only
   after the write `Future` resolves.

   ```dart
   Future<Result<void, TaskFailure>> addTask(Task draft) async {
     try {
       await _db.transaction(() async {
         await _dao.insertTask(draft);            // await — required
       });
       return const Ok(null);                     // committed; the watch stream now re-emits
     } on Exception catch (e) {
       return Err(TaskFailure.write(cause: '$e'));
     }
   }
   ```

## What stays out of the feature

- The feature never sees a Drift symbol — only the value type from the domain/data boundary.
- Derived state (counts, streaks, histograms) is a **second DAO fold over the same rows**, recomputed
  on read — never a stored counter column.
- A new column/table needs a `schemaVersion` bump and a guided, append-only migration with a committed
  schema snapshot and an integrity-check fixture test. Never edit a shipped migration. Do this via
  `run-migration`; the feature scaffold does not author migrations.

Full detail: `persistence-drift` (schema, DAOs, transactions, canonical storage) and `run-migration`
(the forward-only migration ritual).
