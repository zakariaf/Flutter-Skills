# Contributing

This library holds **general, reusable** Flutter skills. Before adding or changing one, make sure it
belongs here and follows the house conventions below.

## What belongs here (and what doesn't)

**In scope** — anything that applies to *any* Flutter app: architecture, state, widgets, async/errors,
naming, lint, performance, docs, testing, persistence, codegen, i18n/RTL, accessibility, value
objects, notifications, native boundaries, CI, dependency hygiene, and **token-agnostic structure**
(how a component / page / view / feature / design-system layer is *organized*).

**Out of scope** — keep these in the individual app's `.claude/skills/`:
- **Design-token values**: specific colours, hex, radii, shadows, elevation, fonts, or magic
  durations. Teaching *how* a token system is structured is fine; prescribing the values is not.
- **App-domain skills**: anything tied to one product's problem space.

Examples must use **neutral generic domains** (`Note`, `Task`, `Product`, `Account`, `Order`,
`Item`, `Reminder`) — never a real app's nouns.

## House conventions

1. **Riverpod 3.x is the default** for state + DI. State/architecture skills lead with a
   state-management-*agnostic* core, give the Riverpod "how", then add a short **Provider /
   `ChangeNotifier` appendix**. Never introduce `get_it`/`injectable`/`package:provider` as a second
   DI container in the Riverpod path. Use the Riverpod 3.0 API: `Notifier`/`AsyncNotifier`/
   `StreamNotifier` base classes (the `AutoDispose*`/`*Family` base classes were removed) with the
   `.autoDispose`/`.family` modifiers on the provider.
2. **Single-package first.** Assume a plain single-package app; fence any monorepo / pub-workspace /
   Melos guidance under a *"when multi-package"* note.
3. **Every code snippet compiles conceptually** — real APIs and real package names only
   (`flutter_riverpod`, `drift`, `freezed`, `go_router`, `intl`, `very_good_analysis`,
   `flutter_local_notifications`, `mocktail`, `alchemist`, …). State limits honestly.

## Canonical stack (keep every skill consistent with these)

New and edited skills must agree with the decisions the existing 37 already follow:

- **Layout:** feature-first — `lib/features/<feature>/presentation/` (dumb View + `<feature>_notifier.dart`)
  over shared `lib/core/` (pure), `lib/data/`, `lib/services/`, `lib/routing/`, `lib/theme/`, `lib/l10n/`.
  `core/` is a sanctioned foundation, **not** a junk-drawer; the app package does not use `lib/src/`
  (that is a package-only convention).
- **ViewModel:** a Riverpod `Notifier`/`AsyncNotifier`/`StreamNotifier` named `<Feature>Notifier` in
  `<feature>_notifier.dart`. `<Feature>ViewModel`/`_view_model.dart` is the Provider-appendix form only.
- **Reactive UI:** a mutation commits through the single repository write path and the watched
  `.watch()` stream **re-emits** — no manual `state = …` republish.
- **Time:** `package:clock`'s `Clock`, injected via `clockProvider` — never `DateTime.now()`, never a
  bespoke `ClockService`.
- **Errors:** `Result<T, F extends Failure>` (typed error arm) everywhere.
- **Boundaries:** `[Concern]Service` for a capability you define; `[Concern]Gateway` for a thin wrapper
  over a specific plugin/SDK or `MethodChannel`.
- **`freezed`** is allowed and preferred for non-trivial value/state types; hand-roll trivial immutables.
- **Complexity numbers** live only in `dart3-idioms-and-coding-standards`; other skills cite that table.

## Skill format

Each skill is a directory under `skills/`. **The directory name is the command name and must equal
the frontmatter `name`** (kebab-case).

```
---
name: my-skill                 # == directory name
description: >-                 # third person; what it enforces THEN "Use when <triggers>".
  ...                          # This is the auto-load trigger — pack it with concrete nouns,
  ...                          # verbs, file names, and symbols a matching task would mention.
                               # Keep under ~1000 chars.
---

# Title
One-sentence philosophy + when it applies.

## Non-negotiable rules      # the heart: each rule + a terse WHY
## <topic sections>          # the "how", with short correct snippets in a generic domain
## Anti-patterns             # "never do this" + the reason it bites
## Definition of done        # a checklist a reviewer can tick
## Related skills            # cross-link siblings by exact name
## References                # official Flutter/Dart/package doc links
```

- The `description` (plus optional `when_to_use`) is truncated at **1,536 characters** in the skill
  listing — keep it dense but well under that; **~1000 chars** is the working cap here.
- Keep `SKILL.md` **lean** (target ≤ ~320 lines). Push depth into `references/`.
- Add `disable-model-invocation: true` **only** for side-effecting runbooks Claude must never fire on
  its own (`run-codegen`, `run-migration`).
- Do not add other frontmatter fields.

### Progressive disclosure (rich skills)

Foundational skills also ship, one directory level deep:

- `references/<topic>.md` — deep-dive material that would bloat `SKILL.md` (tables, edge cases).
- `examples/<name>.dart` — complete, self-contained, correct samples; open each with a `//` comment
  stating what it demonstrates.
- `scripts/<name>.sh` — runnable checks (grep bans, analyze, ARB parity). Start with
  `#!/usr/bin/env bash` + `set -euo pipefail` + a usage comment; accept a target dir arg defaulting to
  `lib/`; hardcode no app-specific paths. Reference bundled scripts from `SKILL.md` via
  `${CLAUDE_SKILL_DIR}` so they resolve at personal, project, or plugin scope.

Simpler skills are a single `SKILL.md`.

## Before opening a PR

```bash
# Structure + manifests
claude plugin validate . --strict

# Scripts parse
find skills -name '*.sh' -print0 | xargs -0 -n1 bash -n

# No design-token values or app-domain wording leaked (spot-check)
grep -rniE 'Color\(0x|BorderRadius\.circular\([0-9]' skills/    # allowed only in design-system-structure / as anti-examples
```

Confirm the new skill is reachable from `flutter-conventions-index` (add it to the routing table),
that its `Related skills` links resolve to real names, and that it doesn't restate a rule another
skill already owns — state it once, cross-reference it elsewhere.
