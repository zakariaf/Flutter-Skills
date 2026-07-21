# Focus, keyboard, and input contracts

The keyboard and focus system is native and stateful. Every `FocusNode` you create is a resource with a lifecycle; every keyboard attribute is a contract with the OS.

## `FocusNode` lifecycle

- Create in `State` (a field), **never in `build()`** — a new node per rebuild loses focus and leaks.
- Dispose every node in `dispose()`. Same rule as controllers (SKILL rule 1).
- If focus state must outlive the widget (multi-step wizard), hold it in a Notifier instead.

```dart
class _CheckoutFormState extends State<CheckoutForm> {
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();

  @override
  void dispose() {
    _nameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }
}
```

You often do not need an explicit `FocusNode` at all — `FocusScope.of(context).nextFocus()` walks the default traversal order. Create nodes only when you need to *target* a specific field (jump to the first invalid field, or advance to a named node).

## Autofocus

Set `autofocus: true` on the field that should receive focus when the form appears (usually the first). Exactly one field per screen should autofocus. On small screens autofocus opens the keyboard immediately — fine for a single-purpose input, disruptive on a long form; choose deliberately.

## Traversal order

Default traversal follows reading order (top-to-bottom, start-to-end, direction-aware so it is correct in RTL — see `i18n-rtl-l10n`). Override only when layout order differs from logical order.

- `FocusTraversalGroup` — scopes a subtree so tab/next stays within it before moving on (e.g. a row of related fields).
- `FocusTraversalOrder` + `NumericFocusOrder` — explicit ordering inside a group when visual order is not logical order.

Prefer laying widgets out in logical order so the default traversal is already correct; reach for explicit ordering last.

## Keyboard action button — `TextInputAction`

`TextInputAction` sets the label/behavior of the on-screen keyboard's action key.

| Value | Meaning |
| --- | --- |
| `TextInputAction.next` | Advance to the next field |
| `TextInputAction.done` | Close keyboard / submit (last field) |
| `TextInputAction.search` | Search-style submit |
| `TextInputAction.newline` | Insert newline (multiline fields) |

Wire the behavior in callbacks — the action value alone only styles the key:

```dart
TextFormField(
  focusNode: _nameFocus,
  textInputAction: TextInputAction.next,
  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(), // advance
),
TextFormField(
  focusNode: _emailFocus,
  textInputAction: TextInputAction.done,
  onFieldSubmitted: (_) => _submit(), // last field submits
),
```

- `onFieldSubmitted(String value)` — fires when the user presses the action key. Best place to advance focus or submit.
- `onEditingComplete` — fires just before submit; default unfocuses. Override to keep focus/customize; usually leave it and use `onFieldSubmitted`.

## Input type and capitalization

These shape the keyboard the OS presents and are structural, not decorative.

- `keyboardType`: `TextInputType.emailAddress`, `.number`, `.phone`, `.url`, `.multiline`, `.datetime`. Wrong type = wrong keyboard = friction.
- `textCapitalization`: `.none` (emails, usernames), `.sentences` (free text), `.words` (names), `.characters` (codes).
- `obscureText: true` for secrets, paired with `autofillHints: [AutofillHints.password]`.

## Autofill

`autofillHints` connects a field to OS autofill and password managers. Omitting it silently breaks a feature users expect.

```dart
TextFormField(
  autofillHints: const [AutofillHints.email],
  keyboardType: TextInputType.emailAddress,
),
```

Wrap a login/signup group in `AutofillGroup` so the platform commits saved credentials together. Use real `AutofillHints` constants (`.email`, `.password`, `.newPassword`, `.name`, `.oneTimeCode`, `.postalCode`, ...).

## Input formatters

`inputFormatters` transform text as it is typed. Structural constraints, never aesthetics.

- `FilteringTextInputFormatter.digitsOnly` — numeric fields.
- `FilteringTextInputFormatter.allow(RegExp(...))` / `.deny(...)` — restrict charset.
- `LengthLimitingTextInputFormatter(n)` — hard cap length.
- A custom `TextInputFormatter` for grouping (e.g. spacing a card number) — return a new `TextEditingValue` and preserve the selection/cursor offset carefully.

Formatters constrain input; they do not replace validation. Keep a `validator` for the final check because paste and autofill can bypass keystroke-level filtering.

## Keyboard avoidance

- `Scaffold.resizeToAvoidBottomInset` defaults to `true`: the body shrinks by the keyboard inset. Put the form in a `SingleChildScrollView` so the focused field can scroll into view.
- For the submit button, either include it in the scroll view or pin it in `bottomNavigationBar` so it is reachable above the keyboard.
- Read the keyboard inset with `MediaQuery.viewInsetsOf(context).bottom` if you need to add manual padding (e.g. above a pinned action bar).

## Dismissing the keyboard

Unfocus on tap-outside or after submit with `FocusScope.of(context).unfocus()` (or `FocusManager.instance.primaryFocus?.unfocus()`). After an async submit, guard with `mounted` before touching focus/context (see `async-safety`).
