# Routing registration & the ARB parity workflow

The two manual steps the generator can't do: register a typed route in the one router, and add the
strings across every locale ARB. Everything else is scaffolded.

---

## A. Register the screen in the ONE go_router

There is a single `GoRouter` for the app, **owned by `navigation-and-routing`** — that skill owns the
router's shell/branch structure, redirect/auth guards, deep links, transitions, and navigator keys. A
feature does **not** get its own router; it only registers ITS route into the existing one. Add a typed
route (`TypedGoRoute` + `GoRouteData`); codegen writes the `.g.dart`.

### Where each screen kind attaches

| Screen kind | Attaches to | Navigator key | Path shape |
| --- | --- | --- | --- |
| A shell tab (list) | a `StatefulShellBranch` | that branch's key | `/<feature>` |
| Master → detail | inside the same branch | the branch key | `/<parent>/:parentId/<feature>/:<feature>Id` |
| Full-screen add/edit | above the shell | `rootNavigatorKey` | child `path: 'new'` / `'edit'` + `parentNavigatorKey` |
| Wizard / import-export | above the shell | `rootNavigatorKey` | a dedicated top-level route |

The shell/branch keys, the redirect guard, and the deep-link payload mapper themselves are defined in
`navigation-and-routing`; the table above only says where this feature's route hangs.

### Canonical typed route

```dart
// app_routes.dart
@TypedGoRoute<TaskDetailRoute>(path: '/projects/:projectId/tasks/:taskId')
class TaskDetailRoute extends GoRouteData with _$TaskDetailRoute {
  const TaskDetailRoute({required this.projectId, required this.taskId});
  final String projectId;   // path param — reconstructable on cold start
  final String taskId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      TaskDetailScreen(projectId: projectId, taskId: taskId);
}

// A full-screen add flow renders ABOVE the bottom nav:
@TypedGoRoute<AddTaskRoute>(path: '/projects/:projectId/tasks/new')
class AddTaskRoute extends GoRouteData with _$AddTaskRoute {
  const AddTaskRoute({required this.projectId});
  final String projectId;
  @override
  Object? get parentNavigatorKey => rootNavigatorKey; // covers the tab bar
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      AddTaskScreen(projectId: projectId);
}
```

### Rules (the ones the feature route itself must honor)

- **Path params carry deep-linkable identity; never `state.extra`.** `extra` is null on cold start,
  reboot, and OS restore — the screen must rebuild its data from the store using the ids.
- **Prefer `.go()` / typed `Route(...).go()`** over `.push()` for primary flows (since go_router 8,
  `push()` no longer updates the location for redirects/URL observers).
- **Navigate from the View or a `redirect`, never from a ViewModel.** The controller publishes state;
  the View or the router decides what is on screen.
- **Full-screen flows set `parentNavigatorKey: rootNavigatorKey`** so the route covers the tab bar.
- Regenerate typed routes: `dart run build_runner build --delete-conflicting-outputs`; a CI freshness
  gate fails on stale route codegen.

The redirect/auth guard the route inherits, explicit branch `navigatorKey`s, and the pure
notification-payload → location mapper are all owned by `navigation-and-routing` — do not redefine
them here or bypass the guard with `Navigator.push`.

---

## B. Add strings across every locale ARB

Inputs live in one l10n directory. `app_en.arb` (or your project's template) is the **template**
(`template-arb-file`). **Every key exists in every locale file** with identical placeholders and ICU
structure.

### Steps

1. **Template first.** Add the message + an `@key` object declaring every placeholder and its `type`
   to the template ARB only.
2. **Mirror into every other locale** with real translations — identical placeholder names, identical
   ICU structure (same plural/select branches; bodies differ per language). RTL locales need their
   CLDR plural forms.
3. **Parity check** (a locale that silently ships English is the failure this catches) — run the
   project's ARB parity script; also invoked by `scripts/verify_feature.sh`.
4. **Regenerate + analyze:** `dart run build_runner build --delete-conflicting-outputs`, then
   `dart analyze`. A missing key becomes a compile error via gen-l10n — the safety net.

### ICU, never concatenation

```json
{
  "tasksTitle": "Tasks",
  "@tasksTitle": { "description": "Title of the tasks list screen" },

  "tasksCount": "{count, plural, =0{No tasks} =1{1 task} other{{count} tasks}}",
  "@tasksCount": {
    "description": "Number of tasks in the current project",
    "placeholders": { "count": { "type": "int" } }
  }
}
```

### Placeholder typing

| ICU intent | `type` | Notes |
| --- | --- | --- |
| plural / cardinal | `int` / `num` | `int` for whole counts, `num` for measured quantities |
| interpolated user text | `String` | preserved verbatim; isolate with bidi if it may be RTL |
| formatted date | `DateTime` + `format` | project through the l10n calendar formatter |
| formatted number/currency | `num` + `format` | number and unit are **separate isolated runs**, never hand-glued |

### Pitfalls

- Adding a key to the template only — every other locale silently ships the template language. Parity catches it.
- Renaming a placeholder in one locale — breaks that translation at runtime. Keep names identical.
- Hand-building "1 day" / "2 days" — use ICU `plural`.
- Forgetting the platform locale manifest (iOS `CFBundleLocalizations`) — the locale is not offered.

See `i18n-rtl-l10n` for the full contract (bidi isolation, numeral normalization, Directional geometry).
