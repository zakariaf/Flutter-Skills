# Commit vs gitignore generated code

There is no universally correct answer. Both strategies work; each trades a
different risk and each *requires* a specific CI gate. Pick one per repo and wire
the gate — an unenforced policy is the only wrong choice.

## Strategy A — gitignore generated code (Dart convention)

`.gitignore` excludes `*.g.dart`/`*.freezed.dart`/`*.drift.dart`/gen-l10n output.
Codegen is the single source of truth on disk.

**Pros**
- Clean diffs and reviews; no generated noise in PRs.
- No merge conflicts in machine output.
- Zero chance of committing stale output — it is never committed.

**Cons**
- A fresh clone cannot `flutter run` until `build_runner` has run.
- The build depends on the generator resolving on the current SDK forever.

**Mandatory CI gate:** codegen is the **first** step of every lane, before
`format`/`analyze`, because a clean checkout has `part '...';` directives
pointing at files that do not exist yet.

```
build_runner build --delete-conflicting-outputs → format → analyze → test
```

## Strategy B — commit generated code

`*.g.dart`/`*.freezed.dart`/`*.drift.dart` are tracked in git.

**Pros**
- `git clone && flutter run` works with no `build_runner` round-trip — the
  minimum bar for an app that must outlive its current toolchain.
- For code where the generated output *is* the contract (e.g. a Drift schema),
  a change shows the real delta as a reviewable diff — review becomes a safety
  gate, not a leap of faith.
- Pins the output against a future generator that emits different code, or one
  that refuses to resolve years later. The committed output still compiles.

**Cons**
- Diff noise (mitigated below).
- Merge conflicts in generated code (negligible for a solo/small team; real at
  scale).
- **Staleness risk** — committed output can silently diverge from its source.

**Mitigation 1 — collapse diff noise** with `.gitattributes`:

```
*.g.dart       linguist-generated=true
*.freezed.dart linguist-generated=true
*.drift.dart   linguist-generated=true
```

GitHub then collapses these files in diffs by default.

**Mitigation 2 — the freshness gate (mandatory).** CI regenerates and asserts no
diff:

```bash
dart run build_runner build --delete-conflicting-outputs
git diff --exit-code -- '*.g.dart' '*.freezed.dart' '*.drift.dart'
```

If this gate is removed, committing generated code stops being safe: the tree can
claim a shape the source would not reproduce, and every reviewer trusts a lie.
For a schema, add the equivalent snapshot dump-and-diff (see `run-migration`).

## Choosing

- Small single app, team comfortable with a build step, values clean reviews →
  **Strategy A**.
- App that must be buildable from a bare clone years later, or where the generated
  output is itself the reviewable contract (schemas) → **Strategy B**.

Whichever you pick, the generated suffixes are excluded from the analyzer and
coverage in *both* cases — committing changes what is on disk, not what tools
should walk.

## One trap that outlives the choice

A tool that generates a *migration test* (e.g. `drift_dev make-migrations`) may
leave the test's data lists empty:

```dart
final oldTasks = <v1.Task>[];
final expectedNewTasks = <v2.Task>[];
// TODO: fill these lists
```

With both lists empty the test passes vacuously (`[] == []`) and proves nothing
while wearing a reassuring name. Fill the lists with hostile realistic rows
(apostrophes, non-ASCII, em dashes, emoji, embedded quotes/backslashes) in the
same commit that generates the test, or delete it. A test that lies is worse than
an absent one. Full ritual: `run-migration`.
