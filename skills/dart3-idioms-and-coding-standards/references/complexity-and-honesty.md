# Complexity limits and honesty bans

Two families of rule the analyzer only partly enforces: the size limits that keep code readable, and the ban on constructs that dodge the type system.

## Complexity limits — firm defaults, not laws

Code is read far more than written; comprehension dominates dev time. These are refactor *prompts* backed by U-shaped fault-density evidence — both too-large and over-fragmented units fault more. **This table is the whole library's single source of truth for these numbers** — `flutter-conventions-index` and `widget-composition` cite it rather than restating figures, so the numbers never drift apart.

| Unit | Limit | Refactor prompt when exceeded |
|---|---|---|
| Method / function | ~30 lines | Extract a named helper, or a value object if it is really doing two jobs. |
| `build()` | ~80 lines | Extract `const` widget classes (never `_buildX()` methods) — see `widget-composition`. |
| File | ~300 lines | Split by declaration; the file should be its primary declaration plus tight satellites. |
| Class public API | ~10 members | The class is doing too much; split responsibilities. |
| Positional params | ~3 (≤ ~4 total) | Pass a value object / named params. |
| Logic nesting depth | ~3 | Early-return / guard clauses; extract the inner block. |
| Widget build nesting depth | ~5 | The one explicit exception — widget trees legitimately nest deeper than logic. Past ~5, extract a `const` subtree widget (see `widget-composition`). |
| Cyclomatic complexity | ~10 | Too many branches; a sealed switch or a lookup table often collapses it. |

Logic nesting (control flow — `if`/`for`/`while`/`try`) caps at ~3; **widget build trees are the deliberate exception and cap at ~5**, because a `Scaffold > body > Column > children > Row` spine is honest structure, not tangled logic. `widget-composition` references this exception rather than restating its own number.

**A cohesive overrun is justified in the PR, not silently split.** A parser or a single state machine scattered across five tiny fragments is a regression, not an improvement — the fragments have to be read together anyway. Keep a cohesive algorithm whole and note why in the PR description. Tools like DCM can enforce these numerically if you want a hard gate; treat the numbers as advisory otherwise.

## Honesty bans — never dodge the type system

Each of these compiles, and each hides a runtime failure the type system would otherwise force you to handle. All are bannable in review.

### No `late` to dodge nullability

`late` disables the null-safety checker and replaces a nullable type with a runtime `LateInitializationError` on first read. Use it **only** for a field that is genuinely initialized exactly once before any read (an injected dependency wired in `initState`), with a comment saying so. Never reach for `late` because a field "is usually set" — that is a nullable field, model it as `T?` and handle the null with `?.`/`??`/promotion.

```dart
// BANNED — hides that the value may be absent.
late Account current;

// OK — genuinely once-initialized, documented.
late final AnimationController _controller; // set in initState, disposed in dispose
```

### No `!` on a value that matters

The null-assertion `!` throws `TypeError` at runtime when it is wrong. It is acceptable on a value the surrounding code has *just* proven non-null (and even then flow promotion usually removes the need). It is banned on any value whose absence is a real possibility — a persistence read, an entitlement, a parsed field, an engine output. Promote instead:

```dart
// BANNED — a null row crashes with no context.
final name = repo.find(id)!.name;

// GOOD — handle the absence.
final account = repo.find(id);
if (account == null) return const AccountLoadFailed();
final name = account.name; // promoted, no `!`
```

### No `dynamic` / `Map<String, dynamic>` as a model

`dynamic` turns every member access into an unchecked runtime dispatch (`avoid_dynamic_calls` should be an error). A `Map<String, dynamic>` flowing through the app as an ad-hoc model is the same hole with extra steps — a typo in a key is a runtime null, field types are unchecked. Parse the map into a typed model at the boundary and pass the model.

```dart
// BANNED — untyped bag, unchecked keys.
void render(Map<String, dynamic> item) => Text(item['title'] as String);

// GOOD — typed at the boundary.
void render(Item item) => Text(item.title);
```

Enable `strict-casts` and `strict-raw-types` in `analysis_options.yaml` (see `lint-and-style-config`) so implicit `dynamic` casts and bare generics are errors, not silent.

### No `throw` for a normal domain outcome

A domain/pure function is total: uncertainty is a return value (a clamped number, a "no result within N steps" outcome, a low-confidence flag), a programmer invariant is an `assert` (stripped in release). `throw` is reserved for truly exceptional conditions handled at an I/O boundary and converted to a typed failure there — see `error-handling-typed-results`.
