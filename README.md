<div align="center">

# 🦋 Flutter Agent Skills

**Production-grade, reusable Flutter engineering skills for AI coding agents.**

Architecture · Riverpod 3.x state · testing · persistence · i18n/RTL · accessibility · navigation · performance — and the codegen/CI/migration runbooks that keep them honest.

[**Browse the catalog →**](https://zakaria.dev/Flutter-Skills/) · [Agent Skills standard](https://agentskills.io) · [Contributing](CONTRIBUTING.md)

`37 skills` · `Riverpod 3.x` · `Material 3` · `works with 70+ agents` · `MIT`

</div>

---

Each skill is a short, high-signal playbook that an agent loads **only when your task matches it**,
then follows — the rules, the anti-patterns, and a definition of done. The rules are applied
consistently across sessions, projects, and agents without bloating context.

Built on the [**Agent Skills**](https://agentskills.io) open standard, so the same files work in
**Claude Code, Cursor, Codex, Copilot, Gemini CLI, Windsurf, Cline, OpenCode** and 70+ more — not
only Claude Code.

These 37 skills were distilled from five production Flutter apps' private skill libraries (~120
skills), merged into one best-of-breed set, reconciled to a single canonical stack, and
adversarially reviewed for API correctness. **Design-token specifics** (exact colours, radii,
shadows, named design systems) and **app-domain skills** were intentionally left out — this is the
general foundation, not any one app's look or domain.

## Quick start

```bash
# Any agent (installs into 70+ tools via the open skills CLI)
npx skills add zakariaf/Flutter-Skills            # all skills
npx skills add zakariaf/Flutter-Skills --list     # browse first
npx skills add zakariaf/Flutter-Skills --skill flutter-architecture
```

Prefer a native integration? See [How to use these skills](#how-to-use-these-skills) below.

## Design principles

- **Riverpod 3.x first, but not Riverpod-only.** State/DI skills lead with a
  state-management-*agnostic* core, give the Riverpod 3.x "how", and close with a **Provider /
  `ChangeNotifier` appendix** so they still serve an app on Flutter's official-guide stack.
- **Single-package first, workspace-aware.** Everything works for a plain single-package app;
  monorepo / pub-workspace / Melos guidance is fenced under *"when multi-package"*.
- **One canonical stack.** Feature-first layout, Riverpod 3.x, `go_router`, Drift, `package:clock`,
  Material 3 — reconciled to a single vocabulary so the 37 skills never contradict each other.
- **Structure, not aesthetics.** Design-system and component skills teach *how* tokens, themes,
  components, pages, and views are **structured** — never "the colour must be `#…`".
- **Progressive disclosure.** Core skills ship a lean `SKILL.md` plus on-demand `references/`,
  `examples/`, and runnable `scripts/`; simpler skills are a single `SKILL.md`.
- **Correct by construction.** Every snippet is idiomatic and conceptually compiles; rules come with
  the *why*, anti-patterns, a definition-of-done, and often a grep/analyze script that enforces them.

## The skills

*Skills marked* ***(rich)*** *ship `references/`, `examples/`, and runnable `scripts/` alongside
`SKILL.md`.* ***(manual-only)*** *skills are side-effecting runbooks an agent never fires on its own.*

### Core Flutter & Dart
| Skill | What it governs |
|---|---|
| `state-management-riverpod` **(rich)** | Riverpod 3.x: one `Notifier`/`AsyncNotifier`/`StreamNotifier` per feature over immutable state, `watch`/`read`/`listen` split, providers-as-DI, `family`+`autoDispose`, single write path. |
| `widget-composition` **(rich)** | Small `const` `Widget` classes over `_buildX()` methods, lean `build()`, dumb Views, key policy, controller disposal, plus structural layout. |
| `dart3-idioms-and-coding-standards` **(rich)** | Which Dart 3 construct each declaration earns: `sealed` + exhaustive `switch`, class modifiers, records intra-layer only, immutable value types, the complexity-limit table. |
| `async-safety` | No-silent-failure async: the arrow-callback `Future`-drop hole no lint catches, `mounted` guards after every `await`, subscription/timer disposal. |
| `naming-conventions` | Effective Dart naming + role suffixes (`Screen`/`Notifier`/`Repository`/`Service`/`Gateway`/`Failure`) so a name reveals the layer. |
| `flutter-performance` | `const` subtrees, rebuilds narrowed via `.select`, lazy lists/slivers, off-isolate work, sized image decode, surgical `RepaintBoundary`, profile-mode measurement. |
| `app-startup-and-bootstrap` | `main()` ordering: crash log + two global error handlers first, settings before `runApp`, composition-root DI overrides, lifecycle flush, no `runZonedGuarded`. |
| `dartdoc-conventions` | `///` on every public API, standalone one-sentence summary, documented units/ranges/throws, `//` explains *why* not *what*. |
| `ui-states-and-feedback` **(rich)** | The non-happy paths: loading/empty/error/content resolved in one `switch`, delayed skeletons, filtered-empty vs empty, typed-`Failure` error text with retry, the inline → snackbar → banner → dialog ladder, Undo over confirm. |
| `forms-and-input` **(rich)** | `Form`/`TextFormField`, sync + async validation, `FocusNode` traversal, keyboard actions, input formatters, error display, controller disposal. |
| `local-notifications-scheduler` **(rich)** | On-device reminders: DB is the only source of truth, one idempotent `syncNotifications()` reconcile, plugin behind a gateway port, DST-correct recurrence, iOS 64-cap budgeting. |

### Architecture
| Skill | What it governs |
|---|---|
| `flutter-architecture` **(rich)** | Right-sized feature-first layered MVVM: features are folders, foundations become packages only when a compile wall earns it, downward-only DAG, single write-path repositories. |
| `navigation-and-routing` **(rich)** | One `go_router` in `lib/routing/`, deep-link identity in path params, redirect guards via `refreshListenable`, `StatefulShellRoute` shells, `PopScope`, 404. |
| `error-handling-typed-results` **(rich)** | Sealed `Result<T,F>` + per-boundary sealed `Failure` returned instead of thrown, exhaustive switches, a global error net, never-lose-data. |
| `service-boundary-and-native` **(rich)** | Every side effect / native channel behind an injectable `Service`/`Gateway` that throws until overridden, one live impl per flavor, `MethodChannel` quarantined to one dir. |

### Structure & foundations
| Skill | What it governs |
|---|---|
| `project-structure-and-packages` **(rich)** | The canonical feature-first tree (`lib/features/` + shared `core`/`data`/`services`/`routing`/`theme`), one public barrel over private `src/`, one-way dependency layering. |
| `design-system-structure` **(rich)** | *Token-agnostic* design-system organization: tokens→theme→modifiers layering, two-tier tokens via `ThemeExtension`, no-raw-values CI gate. |
| `adaptive-layout` **(rich)** | Adapt by size not device: Material 3 window size classes, `LayoutBuilder`/`MediaQuery.sizeOf`, list-detail two-pane, `NavigationRail`-vs-`BottomNav` by width. |
| `custom-canvas-and-gestures` **(rich)** | `CustomPainter` technique: View/Painter/Scene split, `shouldRepaint` as one value compare, one shared transform read by painter *and* hit-tester, gesture→typed-command. |

### Data
| Skill | What it governs |
|---|---|
| `persistence-drift` **(rich)** | Drift/SQLite behind DAOs mapping rows to value objects, schema-level invariants, one-transaction-per-mutation, scoped `.watch` streams, WAL-safe backups. |
| `value-objects-money-and-units` **(rich)** | Store canonically (integer minor units keyed to real ISO-4217 exponent, SI ints, UTC), convert only at the edge, one largest-remainder `allocate()`, inject a `Clock`. |
| `data-export-and-restore` **(rich)** | Portable data: a versioned+checksummed backup envelope, all-or-nothing restore via staging-then-swap, canonical values in machine formats, RFC 4180 + formula-injection-safe CSV, share behind a Gateway. |

### Quality & testing
| Skill | What it governs |
|---|---|
| `testing-strategy` **(rich)** | Test shape follows code not the pyramid: clock-injected pure core, fakes over mocks for owned code, property/fuzz with independent oracles, one acceptance gate. |
| `widget-golden-and-a11y-testing` **(rich)** | `pumpApp` harness with device/`MediaQuery` presets, per-(device,scale,bold) overflow matrix, two golden lanes, RTL goldens, honest a11y limits. |
| `lint-and-style-config` **(rich)** | A strict `analysis_options.yaml`: `very_good_analysis` + `strict-casts`/`strict-raw-types`, silent-failure lints promoted to error, suppression discipline. |

### Internationalization & accessibility
| Skill | What it governs |
|---|---|
| `i18n-rtl-l10n` **(rich)** | gen-l10n/ARB with key+placeholder parity, ICU plurals, `Directional`-only geometry, bidi isolation, canonical-store + localize-at-render, numeral normalize-before-parse. |
| `accessibility-as-code` | A11y as a correctness property: `Semantics` on every node, read a11y flags from `MediaQuery`, never clamp `textScaler`, never colour-alone, 44px targets. |

### Workflows & tooling
| Skill | What it governs |
|---|---|
| `flutter-conventions-index` | The front door: the non-negotiable house rules plus a routing table pointing each task to the right deep-dive skill, and a recommended build order. |
| `scaffold-feature-module` **(rich)** | Stand up one feature: dumb View + 1:1 `Notifier` ViewModel + `widgets/` + scoped providers, single write path, typed `go_router` route, ARB parity. |
| `codegen-and-toolchain` **(rich)** | `build_runner` + toolchain: workspace linking, SDK pinning, per-package `build.yaml`, `--delete-conflicting-outputs`, commit-vs-gitignore, analyzer/coverage excludes. |
| `ci-pipeline-and-gates` **(rich)** | GitHub Actions Flutter CI: pinned toolchain, `format`/`analyze --fatal-infos`, codegen+schema freshness gates, randomized test order, coverage-as-report-not-gate. |
| `dependency-hygiene` **(rich)** | Caret ranges + committed lock, SDK pinning, version-pinned lint include, transitive-tree auditing, vendoring a bus-factor-1 plugin behind an interface. |
| `design-review-workflow` | Once-per-app end-of-build QA sweep: every screen × light/dark × LTR+RTL × largest text × reduce-motion, graded BLOCKER/FIX/NOTE, a dated sign-off that gates release. |
| `release-and-store-shipping` **(rich)** | From green CI to a shipped build: `x.y.z+N` as the only version source, no keys in the repo, archived obfuscation symbols, merged-manifest permission audit, store privacy declarations, size/startup budgets, staged rollout. |
| `run-codegen` *(manual-only)* | The deterministic `build_runner` pass before analyze: the pinned command with `--delete-conflicting-outputs`, never hand-edit or commit-force generated output. |
| `run-migration` *(manual-only)* | The forward-only Drift/SQLite migration ritual: mandatory pre-migration snapshot, bump by one, append-only steps, tests over every from→to path + a forced-throw restore. |
| `run-goldens-rebaseline` *(manual-only)* | The only sanctioned way committed golden images are overwritten: real assertions green first, blessing environment only, inspect every changed PNG, delete orphans, prove it without the flag. |

> A full, searchable catalog with descriptions and filters lives on the
> **[website](https://zakaria.dev/Flutter-Skills/)**.

## How to use these skills

Skills **auto-load** when a task matches their `description` — you rarely invoke them by hand. You
can also run one explicitly with `/<skill-name>` (or, installed as a plugin, `/flutter:<skill-name>`).

### Any agent — the universal installer
```bash
npx skills add zakariaf/Flutter-Skills
```
The open [skills CLI](https://github.com/vercel-labs/skills) places the skills where your agent
expects them (Cursor, Codex, Copilot, Cline, Windsurf, Gemini CLI, …).

### Claude Code — plugin marketplace
```
/plugin marketplace add zakariaf/Flutter-Skills
/plugin install flutter@flutter-skills
```

### Copy into a single project
```bash
git clone https://github.com/zakariaf/Flutter-Skills
mkdir -p .claude/skills && cp -R Flutter-Skills/skills/* .claude/skills/
```

### Personal-global (every project on your machine)
```bash
for d in /path/to/Flutter-Skills/skills/*/; do
  ln -s "$d" "$HOME/.claude/skills/$(basename "$d")"
done
```

### Agents that read `AGENTS.md`
[`AGENTS.md`](AGENTS.md) carries an intent → skill map and usage instructions for any agent (Codex,
Cursor, Copilot, …). Copy its guidance into a consuming project's own `AGENTS.md`.

## Repository layout

```
.
├── .claude-plugin/          # Claude Code plugin + marketplace manifests
├── .codex-plugin/           # Codex plugin manifest
├── AGENTS.md                # cross-agent entry file (intent → skill map)
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md         # frontmatter (name + description) + the playbook
│       ├── references/      # on-demand deep-dives            (rich skills)
│       ├── examples/        # complete, correct .dart samples  (rich skills)
│       └── scripts/         # runnable grep/analyze checks     (rich skills)
├── skills.json              # machine-readable catalog (for tooling & the site)
├── docs/                    # the GitHub Pages website
├── README.md · CONTRIBUTING.md · LICENSE
```

## Validating

```bash
claude plugin validate . --strict          # plugin + marketplace manifests
find skills -name '*.sh' -print0 | xargs -0 -n1 bash -n   # scripts parse
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the skill format, the house conventions every skill must
follow, and the checks to run before opening a PR.

## Provenance

Distilled and merged from the skill libraries of five production Flutter apps, reconciled to one
canonical stack, then adversarially reviewed for API correctness (Riverpod 3.x, Drift, gen-l10n,
WCAG) and scrubbed of design-token and app-domain specifics so they apply to any Flutter app.

## License

[MIT](LICENSE) © 2026 Zakaria Fatahi
