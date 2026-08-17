# AGENTS.md

Guidance for **any AI coding agent** (Claude Code, Codex, Cursor, Copilot, Gemini CLI, Windsurf,
Cline, OpenCode, Antigravity, …) working in a Flutter/Dart project that has these skills installed.

These skills follow the [Agent Skills](https://agentskills.io) open standard, so they work with any
agent that can read Markdown instructions — not only Claude Code.

## What these skills are

Each skill is a short playbook at `skills/<name>/SKILL.md` (or `.claude/skills/<name>/SKILL.md` once
installed into a project) that encodes the non-negotiable rules for one area of Flutter engineering:
architecture, state (Riverpod 3.x), widgets, async safety, testing, persistence, i18n/RTL,
accessibility, navigation, forms, performance, and the codegen/CI/migration runbooks.

The **`description`** in each skill's YAML frontmatter says *when* it applies. Some skills bundle
`references/` (deep-dives), `examples/` (complete `.dart` samples), and `scripts/` (runnable checks).

## How to use them

1. **Before writing or reviewing Flutter/Dart code, check whether a skill applies** — match the task
   to a skill `description`. If one matches, **read that `SKILL.md` (and any reference it points to)
   and follow it**. Do not improvise a different approach when a skill governs the area.
2. **Follow the skill fully**, including its Non-negotiable rules, Anti-patterns, and Definition of
   done. Run any bundled `scripts/*.sh` the skill tells you to before opening a PR.
3. **`flutter-conventions-index` is the front door** — its routing table maps each task to the right
   deep-dive skill and gives a recommended build order. Start there when unsure.

## Intent → skill map

| When you are… | Consult |
|---|---|
| Structuring a project / deciding where code goes | `flutter-architecture`, `project-structure-and-packages` |
| Adding a feature / screen | `scaffold-feature-module`, then the state/widget/nav skills |
| Managing state or dependency injection | `state-management-riverpod` |
| Building or refactoring UI | `widget-composition`, `adaptive-layout`, `design-system-structure` |
| Loading / empty / error states, snackbars, dialogs, Undo | `ui-states-and-feedback` |
| Wiring navigation / routes / deep links | `navigation-and-routing` |
| Building a form or handling input | `forms-and-input` |
| Handling errors / async | `error-handling-typed-results`, `async-safety` |
| Storing data locally | `persistence-drift`, `value-objects-money-and-units` |
| Exporting, backing up, sharing, or restoring user data | `data-export-and-restore` |
| Wiring a side effect or native channel | `service-boundary-and-native` |
| Localizing / RTL | `i18n-rtl-l10n` |
| Accessibility | `accessibility-as-code` |
| Writing tests | `testing-strategy`, `widget-golden-and-a11y-testing` |
| Performance / jank | `flutter-performance` |
| Naming / Dart idioms / docs / lint | `naming-conventions`, `dart3-idioms-and-coding-standards`, `dartdoc-conventions`, `lint-and-style-config` |
| Codegen / CI / dependencies | `codegen-and-toolchain`, `run-codegen`, `ci-pipeline-and-gates`, `dependency-hygiene` |
| Applying a schema migration | `run-migration` |
| Re-baselining golden images | `run-goldens-rebaseline` |
| End-of-build design/QA review | `design-review-workflow` |
| Cutting a release, signing, store declarations, rollout | `release-and-store-shipping` |

## The canonical stack these skills assume

Flutter 3.2x · Dart 3.x · **Riverpod 3.x** for state + DI (with a Provider/`ChangeNotifier` appendix
where relevant) · `go_router` · Material 3 · `drift` for local storage · `intl`/gen-l10n ·
`very_good_analysis`. Skills target a **single-package app by default**; monorepo / pub-workspace
guidance is fenced under *"when multi-package"*.

> **Note for agents editing this repository itself:** the reusable assets are the skills in
> `skills/`. This file is meant to travel *with* the skills into a consuming project — copy its
> "How to use them" and "Intent → skill map" into that project's own `AGENTS.md`.
