---
name: design-review-workflow
description: Enforces one structured end-of-build design/QA pass — never per-task — on the release build: a screenshot sweep matrix (every screen × light/dark × LTR+RTL × largest text scale × reduce-motion) plus an on-device pass on real cheap target hardware, findings graded BLOCKER/FIX/NOTE with every accessibility-floor violation a mandatory BLOCKER, exactly one scoped fix round, and a dated sign-off artifact that gates release. Use when a feature's build tasks are done and it needs its design review, tagging or preparing a release, verifying a build on a physical device, running a pre-ship visual/QA sweep, or asking what design and QA cannot be tested automatically.
---

# Design review workflow

One structured design/QA pass per app or feature, at the very end, on the release build — never a per-task visual critique. During the build, development speed wins and no task is blocked on aesthetics; when the last build task is done and CI is green, exactly one pass runs: a screenshot sweep + an on-device pass → graded findings → one scoped fix round → a dated sign-off that gates release.

## Non-negotiable rules

1. **Once per app/feature, at the end — never per-task.** Blocking a build task on a visual critique, or demanding review screenshots inside a task's acceptance criteria, is the failure this skill prevents. If something looks broken mid-build, file a note and keep moving; review it in the pass.
2. **Trigger = last build task done AND all CI gates + tests green.** Green gates are a *precondition*, not part of the review — this pass judges only what the eye and ear catch. Never re-litigate what CI already proves (determinism, lint, l10n key parity, layer gates).
3. **Review the release build, not a debug build.** A debug banner, debug-mode jank, or an un-overridden status bar wastes the sweep. Standardize the status bar (fixed clock, full battery) so shots differ only where the UI differs.
4. **Sweep the full matrix — every screen the app can show.** Each screen × {light, dark} × {LTR, RTL} × largest text scale × reduce-motion. Dynamic screens get shot in each meaningful state (empty, mid, full/success). One file per matrix cell, machine-sortable names, all artifacts under one review folder inside the write-set.
5. **Every accessibility-floor violation is a BLOCKER — however beautiful the screen.** Contrast, tap-target size, text-scale reflow, color-never-alone, RTL correctness, and reduce-motion safety are the shared floor. A floor miss always grades BLOCKER; aesthetics never buy it back.
6. **Grade every finding BLOCKER / FIX / NOTE.** BLOCKER = floor violation or a shipping-stopper (must fix now); FIX = clearly below bar, fixable this round; NOTE = recorded, deferred to the backlog. Consolidate into one deduped table before fixing.
7. **Exactly one fix round.** Fix BLOCKERs + FIXes as a single scoped unit, re-run gates/tests, re-shoot *only* affected cells (overwrite — the folder stays one truth), verify each finding against its new shot. Open no new critique during verification — new observations become NOTEs. A surviving BLOCKER means no sign-off and an escalation, not a second round.
8. **Do destructive on-device steps last.** Force-stop, previous-release migration, wipe/reinstall, and a deliberate crash each destroy the state before them. Ordering them last means the audio/reader/scale passes aren't redone.
9. **Ship a dated sign-off artifact that gates release.** Date, reviewer, commit sha, build flavor, the matrix inventory, the findings table with resolutions, and a verdict line (SIGNED OFF, or NOT signed off + the escalated blocker). It is a tracked file, not a loose note, and release tasks depend on it.

## The screenshot sweep matrix

Walk every screen in screen order, once per matrix cell. Any screenshot mechanism works — simulator/emulator capture (`xcrun simctl io booted screenshot …`, `adb exec-out screencap`), an integration-test golden harness, or a device screen-grab.

```
Multiplying axes (one still per cell):
  screen    every screen the app can reach + each meaningful state
  theme     light, dark        (flip the OS appearance; leave in-app on "System")
  direction LTR, RTL           (an RTL locale via the in-app locale picker)

Applied to every still (not a separate axis):
  textScale largest supported  (OS font-size max + bold text) — every still is shot under it

Video-only (never a still):
  motion    reduce-motion off, on   (record motion moments as video)
```

- **Name one file per cell, sortable:** `NN--<screen>[-<state>]--<theme>--<dir>.png`. The cell axes are screen×state × theme × direction, so the name needs no textScale or motion token — textScale is applied to every still, and motion evidence is a short video per moment (skippability and the reduce-motion end-state are only judgeable on video).
- **Dark theme must be a designed palette,** not an inverted afterthought.
- **Largest text scale must reflow without truncation or clipping** on the smallest supported device — the case a clamp hides. Never clamp the text scaler to keep a layout tidy; that is a floor violation (see `accessibility-as-code`).
- **RTL cells check:** chrome mirrors, directional insets applied, no bidi garbling in mixed runs, locale-correct numerals, and no missing-glyph tofu in the chosen faces (see `i18n-rtl-l10n`).

## Grading rubric

Critique each screen through four lenses; grade each finding.

- **Floor compliance (absolute).** Contrast on the worst offender per screen in both themes, every daily-flow control at a real minimum tap size, desaturate a shot to prove no state relies on color alone, reduce-motion shows instant end-states, RTL correct. Any miss = **BLOCKER**.
- **Identity fidelity.** Does the screen deliver the app's declared design language (its theme/tokens/components) — not a generic default? Judge delivery of the *declared* identity; changing the identity is a design-system amendment, out of scope here.
- **Parity or better.** Where a prototype, spec, or prior reference exists, the built screen matches its intent and exceeds its execution (real motion, real fonts, crisper spacing). A screen where the reference looks better is a FIX at minimum.
- **Motion moments.** Every declared animation lands, is skippable (a tap mid-animation resolves to the end state), and has a reduce-motion path. Declared-but-missing = FIX; a success state with no feedback at all = BLOCKER.

| Grade | Meaning | Action |
|---|---|---|
| BLOCKER | floor violation or shipping-stopper | fix this round; gates sign-off |
| FIX | clearly below bar, cheap to fix | fix this round |
| NOTE | minor / subjective / deferrable | record to backlog, ship anyway |

## The on-device pass

Screenshots prove layout; they never prove behavior. Run one pass on **real, cheap, target-class hardware in real state** — a device farm and a flagship both hide the bugs the median user hits.

- **Real target hardware, not an emulator,** for anything an emulator can't reproduce: audio/haptics/native surfaces, real fonts, memory pressure on budget silicon, real system settings.
- **The device in the user's real state:** silent mode / ringer off, the shipped release build (obfuscation and split-debug-info only manifest in release), whatever accessibility services the audience uses.
- **Screen-reader + switch-access traversal** on the key screens: every interactive element reachable and correctly labeled, no focus trap, every mode (edit, text entry) exitable using only the assistive service. Text fields are the classic trap.
- **Largest system font + bold + display zoom** on the smallest device: nothing clipped, layout intact.
- **Data-safety rehearsal (destructive, do last):** install the previous release, create data, upgrade in place — data intact (a schema-shape CI check passes on a migration that copies zero rows; see `run-migration`). Then export → wipe/second device → import, and feed import a truncated and a hand-corrupted file — a visible error, never a wiped store.
- **Crash-log line of sight (do last):** trigger a known crash, export the log, confirm readable symbol names (hex offsets mean debug info leaked out of the build) and that the log carries no user content.

Track it as a checklist ticked fresh before every tag — never tag from memory of "basically doing this last time." Record device, OS version, and date at the top; when a check fails, that header is the entire reproduction context.

## Turn design rules into a greppable gate (methodology, not a fixed list)

The eyeball half of a review doesn't scale and regresses silently. Encode the *mechanically checkable* subset of your design rules as a grep-based CI gate so a banned construct can't re-enter unreviewed.

```bash
#!/usr/bin/env bash
set -euo pipefail
# Fails if a raw color/value that must come from the design-system layer
# appears in a widget file. Tune the patterns to YOUR rules.
target="${1:-lib/}"
if grep -rnE 'Colors\.(white|black)|Color\(0xFF' "$target" \
     --include='*.dart' | grep -v '/theme/'; then
  echo "Raw color outside the theme layer — a decision must exist here." >&2
  exit 1
fi
```

- **A hit is not automatically a defect — it is a place a decision must exist.** Resolve each hit or record why the code is right; never blanket-suppress.
- **Be honest about the un-greppable half.** Composition, color harmony, copy register, and radius-to-size ratios pulled from tokens do not grep. A clean script run passed the greppable half only — never report it as "the screen passes the review."
- Keep the specific values in your design system (see `design-system-structure`); this gate only enforces that they're *sourced from there*.

## Anti-patterns

- **Per-task design review** — critiquing pixels mid-build; the exact failure this skill exists to prevent.
- **Reviewing a debug build** or an un-standardized status bar — wasted, noisy shots.
- **A second fix round, or quiet iteration on a surviving BLOCKER** — one round, then sign-off or escalation.
- **Re-testing what CI already proves** — determinism, lint, l10n parity are the precondition, not the rubric.
- **Clamping the text scaler** to keep a layout tidy — hides the truncation the largest-scale cell exists to catch; it's a floor violation.
- **A device-farm or flagship-only on-device pass** — both hide the budget-hardware and real-state bugs.
- **Skipping RTL because the OS has no device locale for it** — the in-app locale picker is the shipping path and the sweep's hardest case.
- **Reporting a clean grep gate as a passed review** — it only ever covered the mechanical half.
- **A loose sign-off note** — it must be a tracked artifact release depends on.

## Definition of done

- [ ] Trigger verified: last build task done, CI gates + tests green; review runs on the release build.
- [ ] Full matrix shot: every screen (× states) × light/dark × LTR/RTL × largest text scale × reduce-motion, one sortable file per cell in the review folder.
- [ ] Motion moments captured as video; largest-scale reflow re-shot on the smallest device.
- [ ] Four lenses applied per screen; every finding graded; every floor violation graded BLOCKER.
- [ ] On-device pass on real cheap target hardware in real state: reader + switch traversal, scaling, migration + export/wipe/import + corrupt-file, crash-log symbols/no-user-content — destructive steps last.
- [ ] One fix round: BLOCKERs + FIXes fixed, gates/tests re-run, affected cells re-shot (overwriting), each finding marked resolved/deferred, no new critique opened.
- [ ] Greppable design-rule gate run (if one exists); each hit resolved or justified.
- [ ] Dated sign-off artifact written (date, reviewer, sha, flavor, inventory, findings + resolutions, verdict line); NOTEs moved to the backlog.

## Related skills

- See `design-system-structure` for the token/theme layering whose delivery this pass judges and whose raw-value gate this workflow runs.
- See `accessibility-as-code` for the floor (Semantics, tap targets, never-clamp-textScaler, color-never-alone) that every BLOCKER enforces.
- See `i18n-rtl-l10n` for the RTL/bidi/numeral correctness the sweep's RTL cells check.
- See `widget-golden-and-a11y-testing` for the automated overflow/golden/RTL matrix that this manual pass complements, not replaces.
- See `run-migration` for the migration ritual the data-safety rehearsal exercises.
- See `ci-pipeline-and-gates` for where the greppable gate and the green-before-review precondition live.
- See `motion-and-haptics` for the declared moments this sweep records on video with reduced motion on and off.
- See `release-and-store-shipping` for the release this pass's dated sign-off gates, and `run-goldens-rebaseline` for re-baselining the goldens an accepted visual FIX moved.
- See `ui-states-and-feedback` for the empty/error/loading states the sweep shoots as their own matrix cells.

## References

- Flutter accessibility: https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility
- Testing accessibility on device (screen reader, switch access): https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility#testing-your-apps-accessibility
- Internationalization & RTL: https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization
- Material 3 accessibility guidance: https://m3.material.io/foundations/accessible-design/overview
- WCAG 2.2 contrast & target-size: https://www.w3.org/WAI/WCAG22/quickref/
- `flutter build` (release, obfuscation/split-debug-info): https://docs.flutter.dev/deployment/obfuscate
