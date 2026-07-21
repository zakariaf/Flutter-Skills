# Coverage, suite budget, and the manual handoff

## No global percentage gate — floor the unrecoverable files

A 100%-coverage gate's rationale is confidence-under-change, and it is defensible for a
large team where it removes subjective per-file arguments. A small project collects less
of that benefit and pays the full cost; a self-imposed global gate gets bypassed or
gamed, and it rewards vanity tests plus exclusion churn.

Instead, hold a **100% floor on the specific files where a bug is unrecoverable** — and
it must be **files, not directories**. This floor is enforced by **human diff-review**
(the reviewer confirms a new or changed unrecoverable-bug file carries its tests), not
by an automated coverage-percentage gate — `ci-pipeline-and-gates` (rule 8) publishes
coverage as a report and gates nothing on a threshold:

| File class | Why a gap is unrecoverable |
|---|---|
| Schema migrations | A botched migration silently drops rows — irreplaceable user data, no rollback. |
| The money/`allocate` primitive | An off-by-one loses or invents value in every downstream total. |
| A parser over an untyped wire format | A wire-format trap silently inverts a safety property in the direction that hurts. |
| The crash/diagnostic log | The only field signal there is; a gap there is blindness. |

Directories fail as the unit because a directory usually also holds a
plugin-wrapper/generated file that cannot reach 100% while channel mocking stays
confined to one file — a directory floor there is jointly unsatisfiable. An explicit
file list is not.

Elsewhere, publish coverage as a report and watch the trend in review — no fixed target
and no automated percentage gate (`ci-pipeline-and-gates` owns that call); a drop is a
prompt to look at the diff, not a red build. Every test must still end in a meaningful
`expect`; a covered line that asserts nothing is worthless.

## Fix the coverage-lies-upward gap first

`flutter test --coverage` **omits files that no test imports** — an untested file
contributes zero lines to the *denominator* instead of counting as 0%. One well-tested
file plus twenty untested ones can report ~100%. **The number lies upward**, which is
the unsafe direction: a coverage number that overstates safety is worse than none.

Fix it before reporting, either way:
- `dlcov --include-untested-files=true`, or
- a generated `test/coverage_helper_test.dart` that imports every file under `lib/`.

Then strip generated code (confirm which extensions your codegen actually emits):

```bash
lcov --remove coverage/lcov.info \
  'lib/**/*.g.dart' \
  'lib/**/*.freezed.dart' \
  'lib/**/*.drift.dart' \
  -o coverage/lcov.info \
  --ignore-errors unused   # lcov 2.x errors on patterns that match nothing
```

Mirror these excludes exactly in the analyzer/coverage config so a file is not counted
in one tool and ignored in another.

## The suite-time budget

Put a wall-clock budget on the default `flutter test` lane (a small app should stay in
the tens of seconds) and treat it as a fixed account, not a floor:

- A suite that costs minutes gets skipped, and a skipped suite is a distrusted one —
  in a project with no telemetry, a distrusted suite means nothing stands between users
  and a silent failure.
- Any test that costs seconds — a real device, a `sleep`, a network wait, an unbounded
  `pumpAndSettle` — must justify itself against the budget or move to the manual pass.
- A proposal that grows one suite is spending from the account and must say what it
  bought. More tests of the same shape cannot refill a missing discovery channel.

## Randomize test ordering

Run with a randomized seed (`--test-randomize-ordering-seed random`) so a hidden
inter-test dependency (shared static state, a leaked handler, an un-disposed container)
surfaces as a flake in CI rather than in the field. Fresh instances in `setUp`, no
cross-test mutable state.

## Hand structurally-untestable paths to a named manual pass

Some high-severity failures are unreachable by every automated means available. Do not
write a test that appears to cover them — a green test that proves nothing stops anyone
checking by hand. Enumerate them in a tracked, dated checklist ticked before every
release, on the **release build** on **real hardware**:

- Real audio / camera / sensor output — no API captures the actual device output.
- OEM device diversity, battery-killer/Doze survival, boot re-arm — one emulator
  samples zero of it; a farm runs the same images.
- Native surfaces with **no Flutter engine** (a home-screen widget, a Quick Settings
  tile) — no Flutter test of any level can reach them.
- The **prior-release migration rehearsal**: install the previous release, create and
  edit data, upgrade in place, assert every row survives. The CI schema-shape check is
  blind to rows and passes green on a migration that copies zero of them. Also rehearse
  export → wipe → import through the real share sheet, and feed import a truncated and a
  hand-corrupted file to confirm a visible error rather than silent data loss.
- Screen-reader double-tap *audibly heard*, and no surface a **focus trap** — the
  automated suite pins traversal order and labels but cannot hear output or prove
  escapability.

State each exclusion in a comment where it happens (the excluded enum value, the
untested file), not only in a tracker, so the reason travels with the code and does not
get re-litigated.
