---
name: naming-conventions
description: Enforces Effective-Dart casing (UpperCamelCase types, lowerCamelCase members/constants, lowercase_with_underscores files) plus architectural role suffixes so a name or grep reveals the layer — Screen/Notifier/Repository/Dao/Service/Gateway/Failure, file=primary-declaration, units-and-semantics in identifiers, booleans as is/has/can/should assertions, no get-prefix, no Hungarian, no SCREAMING_CAPS, grouped-and-sorted imports. Use when creating a file, naming a class/enum/mixin/extension/typedef/variable/function/getter/constant/parameter, organizing imports, choosing a role suffix, or reviewing a diff for naming and directive ordering.
---

# Naming Conventions

Consistent, role-carrying names make code searchable and self-explaining, and the suffix on a type declares which layer it lives in — so a reviewer, a `grep`, and a banned-import gate can all read the layer off the name alone. This skill is the *how*; the normative *what* is [Effective Dart](https://dart.dev/effective-dart). Never invent a house style that contradicts the language's own.

## Non-negotiable rules

1. **Types are `UpperCamelCase`.** Classes, enums, mixins, extensions, typedefs, type parameters: `TaskScreen`, `OrderStatus`, `Predicate<T>`. Consistent shape makes types visually distinct from values.
2. **Members, variables, functions, and parameters are `lowerCamelCase`.** `dueDate`, `loadTasks()`, `itemCount`. It is the language default; deviating costs readers a double-take.
3. **Constants are `lowerCamelCase`, never `SCREAMING_CAPS`.** `const maxItemsPerPage = 50;` — not `const MAX_ITEMS = 50`. Dart dropped the C convention; the analyzer expects `constant_identifier_names`.
4. **Files, folders, libraries, and import prefixes are `lowercase_with_underscores`.** `task_detail_screen.dart`, `features/task_detail/`, `import 'package:app_core/app_core.dart';`. Cross-platform filesystems and pub demand it.
5. **File name = its primary declaration, snake_cased, one primary public type per file.** `TaskNotifier` lives in `task_notifier.dart`. No `utils.dart`/`helpers.dart`/`models.dart` grab-bags and no `utils/`/`common/`/`helpers/`/`misc/` junk-drawer folders — a reader who greps a symbol must land in the file that owns it. `core/` is the *sanctioned* pure-foundation layer (value objects, `Result`/`Failure`, the `Clock` seam, pure calculators), not a junk-drawer — see `project-structure-and-packages`, which owns the layout.
6. **Acronyms longer than two letters are cased like a word.** `Json`, `Http`, `Url`, `Api` → `JsonOrder`, `HttpClient`, `fromJson`, `imageUrl` — not `JSONOrder`, `HTTPClient`. Two-letter caps-in-English acronyms may stay caps as types (`ID`, `UI`). Mixed-case acronyms are unsearchable and inconsistent.
7. **A leading underscore means library-private — use it only when you mean private.** Never prefix a public symbol with `_` to "namespace" it; that makes it unusable from another file. Public (no `_`) is a documented contract — see `dartdoc-conventions`.
8. **No Hungarian / type-encoding in names.** Not `strName`, `iCount`, `lstItems`, `userMap`, `nameString`, `itemsList`. The type system already knows the type; write `name`, `usersById`, `items`.
9. **Full dictionary words; units and semantics live in the name.** `maxItemsPerPage`, `retryDelaySeconds`, `orderTotalMinorUnits` — never bare `max`, `delay`, `total`. Abbreviations (`opt`, `qty`, `amt`) are confined to the inside of one short pure function with a comment mapping them. A name that omits its unit invites a unit bug.
10. **Booleans read as assertions.** `isLoading`, `hasError`, `canSubmit`, `shouldRetry` — not `loading`, `error`, `retry`. Boolean getters and methods start `is`/`has`/`can`/`should` so a condition reads like prose.
11. **No `get`-prefixed accessors.** Expose `dueTasks`, not `getDueTasks()`. Dart has real getters. Functions are verb phrases (`loadTasks()`, `scheduleReminder()`); non-boolean getters are noun phrases (`itemCount`, `nextDueDate`).
12. **Imports grouped and sorted:** `dart:` first, then `package:`, then relative — each group alphabetized, `export`s in their own section after imports. Let `dart format` plus the `directives_ordering` lint enforce it; never hand-fight the formatter.

## The suffix declares the layer

A role suffix turns a name into a layer contract: a `grep` or a path-scoped import gate can tell a repository from a view from a platform boundary without opening the file. Use neutral domain nouns (Task, Order, Account, Item) for the entity token.

| Role | Suffix / pattern | Layer | File → symbol |
|---|---|---|---|
| Screen / route target | `[Feature]Screen` | UI (View) | `task_list_screen.dart` → `TaskListScreen` |
| Reusable widget | `[Thing]` (+ `Widget` only if ambiguous) | UI | `task_card.dart` → `TaskCard` |
| ViewModel (Riverpod, default) | `[Feature]Notifier` | UI (ViewModel) | `task_list_notifier.dart` → `TaskListNotifier` |
| ViewModel (Provider appendix only) | `[Feature]ViewModel` | UI (ViewModel) | `task_list_view_model.dart` → `TaskListViewModel` |
| Repository (interface) | `[Entity]Repository` | data | `task_repository.dart` → `TaskRepository` |
| Repository (impl) | `Drift[Entity]Repository` / `Remote[Entity]Repository` | data | `drift_task_repository.dart` |
| Drift DAO | `[Entity]Dao` | data | `tasks_dao.dart` → `TasksDao` |
| Capability interface you define | `[Concern]Service` | boundary | `share_service.dart` → `ShareService` |
| Service impl (per flavor) | `[Provider][Concern]Service` | app adapter | `firebase_analytics_service.dart` → `FirebaseAnalyticsService` |
| Wrapper over a specific plugin/SDK/native channel | `[Concern]Gateway` | boundary | `notification_gateway.dart` → `NotificationGateway` |
| Gateway impl | `[Plugin][Concern]Gateway` / `Live[Concern]Gateway` | app adapter | `fln_notification_gateway.dart` → `FlnNotificationGateway` |
| Pure-Dart domain logic | `[Domain]` + verb suffix (`Calculator`/`Validator`/`Formatter`) | domain | `price_calculator.dart` → `PriceCalculator` |
| Immutable model | domain noun, no suffix | any | `task.dart` → `Task` |
| Failure type | `[Domain]Failure` (sealed) | any | `order_failure.dart` → `OrderFailure` |

- **`Notifier` is the ViewModel role — never `ViewModel` or `ChangeNotifier` in the type name.** On Riverpod 3.x the ViewModel is a `Notifier`/`AsyncNotifier`/`StreamNotifier`, one per `Screen`, 1:1, named `[Feature]Notifier` in `[feature]_notifier.dart` (file = primary declaration). `[Feature]ViewModel` in `[feature]_view_model.dart` is sanctioned ONLY in the Provider/`ChangeNotifier` appendix — never on the Riverpod path, and never `[Feature]Controller`. See `state-management-riverpod`.
- **`Service` vs `Gateway` — both name provider-free boundary ports, distinguished by who owns the contract.** A `[Concern]Service` is a capability interface YOU define (`ShareService`, `AnalyticsService`); a `[Concern]Gateway` is the thin wrapper over a SPECIFIC external plugin/SDK or native `MethodChannel` (`NotificationGateway` over `flutter_local_notifications`, `SecureStorageGateway` over `flutter_secure_storage`). Domain and UI code names the interface; the concrete impl (`FirebaseAnalyticsService`, `FlnNotificationGateway`) lives only in the composition root. A concrete impl name leaking into shared code is a grep-catchable smell. See `service-boundary-and-native`.
- **Pure-Dart types carry a `Calculator`/`Validator`/`Formatter`/`Parser` verb suffix and touch no Flutter.** The suffix advertises that the type is framework-free and unit-testable without a widget.
- **Match the domain's ubiquitous language and keep it consistent everywhere** — one word per concept across models, repositories, and UI, so search finds every reference.

## Value vs. instant, and other name-carried distinctions

Encode a semantic distinction the type system can't in the name. A raw instant (`DateTime.now()`) used where a stable calendar value is expected is a common correctness bug; naming makes the boundary visible.

```dart
// A real wall-clock instant is legal only at the Clock boundary and named as one.
final DateTime capturedAt = clock.now();      // instant, from package:clock's Clock (never DateTime.now())

// A stored quantity carries its canonical unit in the name.
final int priceMinorUnits;                    // not `price` — unit is explicit
final int distanceMeters;                     // SI base unit, integer

// Unused callback params are `_` (and `__` for a second).
onChanged: (_) => notifier.refresh(),
```

See `value-objects-money-and-units` for canonical storage and `service-boundary-and-native` for the `Clock` (from `package:clock`) injected via `clockProvider` — never a bespoke `ClockService`.

## Worked example

```dart
// task_list_notifier.dart — file name == primary declaration, snake_cased
import 'dart:async'; // dart: group, alphabetized

import 'package:flutter_riverpod/flutter_riverpod.dart'; // package: group, alphabetized

import 'task.dart'; // relative group, alphabetized

/// Frozen paging bound — unit lives in the name (rule 9).
const int maxItemsPerPage = 50; // lowerCamelCase const, not SCREAMING_CAPS

/// ViewModel for [TaskListScreen]. One Notifier per Screen, 1:1 (role suffix).
class TaskListNotifier extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() => ref.watch(taskRepositoryProvider).loadTasks();

  /// Verb-phrase command; routes through the repository's single write path.
  Future<void> archive(String taskId) async {
    await ref.read(taskRepositoryProvider).archive(taskId);
    ref.invalidateSelf();
  }

  bool get hasTasks => state.valueOrNull?.isNotEmpty ?? false; // boolean assertion
  int get taskCount => state.valueOrNull?.length ?? 0;          // noun getter, no get- prefix
}
```

## Anti-patterns

- `SCREAMING_CAPS` constants in new Dart (`const MAX_ITEMS = 50`) — use `lowerCamelCase`; the analyzer flags it.
- Class name ≠ file name (`TaskScreen` living in `home.dart`), or a grab-bag `utils.dart`/`models.dart` holding unrelated things — breaks grep-to-file.
- Naming a Flutter-touching type `…Calculator`/`…Validator` (a pure-Dart suffix), or a Riverpod ViewModel `…ViewModel`/`…VM`/`…Controller` — the suffix then lies about the layer (`…Notifier` on the Riverpod path; `…ViewModel` only in the Provider appendix).
- A concrete impl name (`FlnNotificationGateway`, `FirebaseAnalyticsService`) referenced from shared/domain code — name the `Gateway`/`Service` interface; the impl belongs in the composition root.
- `DateTime.now()` captured into a field meant to be stable, or an unnamed instant crossing into domain logic — inject a `Clock` and name the instant (`capturedAt`).
- `getDueTasks()` / `get`/`set` prefixes — Dart has real getters.
- Type baked into a name: `userMap`, `nameString`, `itemsList`, `strName`, `iCount`.
- Booleans without `is`/`has`/`can`/`should` (`loading`, `valid`); unit-silent quantities (`total`, `delay`).
- Leading `_` to "namespace" a public symbol (it makes it private and unreachable); `l`/`O`/`I` single letters or `data`/`temp`/`foo` in committed code.
- Abbreviations (`opt`, `qty`, `msg`) outside a single short function with a mapping comment.
- Hand-sorted or mixed import groups — run `dart format`; obey `directives_ordering`.

## Definition of done

- [ ] Types `UpperCamelCase`; members/vars/constants `lowerCamelCase`; files/folders/prefixes `lower_snake_case`.
- [ ] File name matches its primary declaration; one primary public type per file; no junk-drawer file or folder.
- [ ] Architectural suffix applied and correct for the layer (`Screen`/`Notifier`/`Repository`/`Dao`/`Service`/`Gateway`/`Failure`).
- [ ] Riverpod ViewModels are `…Notifier` (not `…Controller`/`…ViewModel`/`…VM`); pure-Dart types carry a `Calculator`/`Validator`/`Formatter` suffix and no Flutter import; `Service`/`Gateway` interfaces are provider-free with impls confined to the composition root.
- [ ] Acronyms >2 letters word-cased; full dictionary words; units + semantics in the name; instants named at the `Clock` boundary.
- [ ] Booleans read as assertions; functions are verb phrases; getters are noun phrases with no `get` prefix.
- [ ] Imports grouped `dart:`/`package:`/relative and alphabetized; `dart format` + `dart analyze --fatal-infos` clean.

## Related skills

- `dart3-idioms-and-coding-standards` — which construct (sealed/record/enum) each declaration earns, and complexity limits.
- `state-management-riverpod` — why the ViewModel is a `Notifier`, and the single write path.
- `service-boundary-and-native` — provider-free `Service` interfaces and their composition-root impls.
- `value-objects-money-and-units` — canonical-unit storage behind the unit-in-name rule.
- `naming` neighbors: `dartdoc-conventions` for the `///` contract on public symbols, `lint-and-style-config` for the `directives_ordering`/`constant_identifier_names` enforcement, and `flutter-architecture` for the layer DAG the suffixes map to.

## References

- [Effective Dart: Style](https://dart.dev/effective-dart/style) — casing, file names, import ordering (normative).
- [Effective Dart: Design — naming](https://dart.dev/effective-dart/design) — booleans, getters vs. methods, verb/noun phrasing.
- [Dart linter rules](https://dart.dev/tools/linter-rules) — `constant_identifier_names`, `camel_case_types`, `file_names`, `directives_ordering`, `non_constant_identifier_names`.
