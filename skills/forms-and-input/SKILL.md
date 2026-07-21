---
name: forms-and-input
description: Enforces Form + GlobalKey<FormState> with TextFormField whose sync validator returns a localized String? (never a hardcoded literal), AutovalidateMode.onUserInteraction, async availability checks moved OUT of the sync validator into a debounced Riverpod Notifier that surfaces errors through state, FocusNode/TextInputAction/onFieldSubmitted traversal, keyboardType/textCapitalization/autofillHints/TextInputFormatter, mandatory TextEditingController/FocusNode disposal, submit-enabled derived from validity (not stored), and scoped rebuilds so a keystroke never rebuilds the whole form. Use when building a Form, TextFormField, or FormField; wiring sync or async validation; managing FocusNode, focus traversal, autofocus, TextInputAction, onFieldSubmitted, or onEditingComplete; setting keyboardType, autofillHints, textCapitalization, or InputFormatter; disposing TextEditingController/FocusNode; enabling/disabling a submit button; or handling keyboard-avoidance on submit.
---

# Forms and input

Text input is where most disposal leaks, un-localized strings, and jank enter a Flutter app. A form is a small state machine: fields hold text, a `FormState` validates them, and a ViewModel owns anything that touches the network or the clock. Keep those three responsibilities separate.

Read the reference for the task at hand:

- `references/validation-sync-and-async.md` — sync `validator` returning localized `String?`, `AutovalidateMode` choice, and the debounced-async-in-a-Notifier pattern (why async must NOT live in the sync validator).
- `references/focus-and-keyboard.md` — `FocusNode` lifecycle, traversal order, `autofocus`, `FocusTraversalGroup`, `TextInputAction`, `onFieldSubmitted`/`onEditingComplete`, `keyboardType`, `autofillHints`, `TextInputFormatter`, keyboard-avoidance.

Run `scripts/check_forms.sh` before a PR.

## Non-negotiable rules

1. **Every `TextEditingController` and `FocusNode` created in a `State` is disposed in `dispose()`.** They hold native resources and listeners; a leak survives the widget and fires callbacks against a dead tree. If the value must outlive the widget, hold it in a Notifier instead — see `state-management-riverpod`.
2. **Validator messages are localized, never hardcoded.** A `validator` returns `AppLocalizations.of(context).fieldRequired`, not `'Required'`. Error text is user-facing UI copy and is owned by `i18n-rtl-l10n`. The `check_forms.sh` grep fails on string literals returned from a validator.
3. **The sync `validator` is pure and instant — no `await`, no network, no `Future`.** `FormFieldValidator<T>` is `String? Function(T?)`; it cannot be async and Flutter calls it synchronously during layout. Availability/uniqueness checks belong in a Notifier (rule 4).
4. **Async validation lives in a debounced Riverpod Notifier and surfaces through state.** Debounce with a `dart:async` `Timer` (kept deterministic in tests via `fakeAsync`, not by the clock), run the check, and expose `AsyncValue`/a sealed status the field reads via `InputDecoration.errorText`. Any *timestamp* the check records comes from `ref.read(clockProvider).now()`, never `DateTime.now()` — the Clock seam is owned by `service-boundary-and-native`. Never block a keystroke on I/O. See `async-safety` for cancel-on-dispose.
5. **Submit-enabled is DERIVED from validity, never stored as a separate `bool`.** A stored `_isValid` flag drifts out of sync with the fields. Compute it from `FormState`/Notifier state at build time. See `flutter-performance` (derive-don't-store).
6. **A keystroke rebuilds one field, not the whole form.** Give each field its own controller/`FormField`; do not lift raw text into a top-level `setState`/`watch` that rebuilds every sibling. Scope rebuilds with small widgets and `ref.watch(....select(...))`. See `widget-composition` and `flutter-performance`.
7. **Choose `AutovalidateMode` deliberately.** Default to `AutovalidateMode.onUserInteraction`: silent until the user touches a field, then live. Never `always` (screams before the user types). Validate-on-submit only for short forms where per-field feedback is noise.
8. **Keyboard type, capitalization, and autofill are declared per field.** `keyboardType`, `textCapitalization`, `autofillHints`, and `TextInputFormatter`s are structural input contracts, not decoration. A missing `autofillHints` breaks OS autofill and password managers.
9. **Errors are announced, not just colored.** `InputDecoration.labelText`/`errorText` carry semantics that screen readers read on change; never signal an error with color alone. See `accessibility-as-code`.

## Form skeleton

`Form` + a `GlobalKey<FormState>` is the coordination point. The key lets the submit handler call `validate()`/`save()` across all fields at once.

```dart
class TaskForm extends StatefulWidget {
  const TaskForm({super.key, required this.onSubmit});
  final void Function(String title) onSubmit;

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _titleFocus = FocusNode();

  @override
  void dispose() {
    _titleController.dispose(); // rule 1: always dispose
    _titleFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSubmit(_titleController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction, // rule 7
      child: Column(
        children: [
          TextFormField(
            controller: _titleController,
            focusNode: _titleFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.taskTitleLabel),
            validator: (value) => // rule 2 + 3: localized, pure
                (value == null || value.trim().isEmpty) ? l10n.fieldRequired : null,
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
  }
}
```

## Sync validation

The `validator` is a total, synchronous function of the field value. Return `null` for valid, a localized message otherwise. Compose small checks; keep the closure short.

```dart
String? validateTitle(String? value, AppLocalizations l10n) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return l10n.fieldRequired;
  if (text.length > 120) return l10n.fieldTooLong; // structural bound, not design
  return null;
}
```

## Async validation (out of the validator)

An availability check (is this account name taken?) is I/O. It runs in a Notifier, debounced against `clockProvider`, and the field reads the result through `errorText`. The sync `validator` stays pure and only guards the shape of the input. Full pattern in `references/validation-sync-and-async.md` and `examples/async_field_notifier.dart`.

```dart
// The field is driven by Notifier state, not by an async validator.
final status = ref.watch(nameAvailabilityNotifierProvider);
TextFormField(
  controller: _nameController,
  onChanged: ref.read(nameAvailabilityNotifierProvider.notifier).onNameChanged,
  decoration: InputDecoration(
    labelText: l10n.accountNameLabel,
    errorText: switch (status) {
      AsyncData(:final value) when value == NameCheck.taken => l10n.nameTaken,
      AsyncError() => l10n.nameCheckFailed,
      _ => null, // idle / loading / available: no error
    },
  ),
);
```

## Focus and keyboard flow

`TextInputAction.next` moves to the next field; `.done` submits. Advance focus in `onFieldSubmitted` with `FocusScope.of(context).nextFocus()` or by requesting a specific node. Group related fields with `FocusTraversalGroup` to control tab order. Details in `references/focus-and-keyboard.md`.

```dart
TextFormField(
  focusNode: _titleFocus,
  textInputAction: TextInputAction.next,
  onFieldSubmitted: (_) => _dueDateFocus.requestFocus(),
),
```

## Submit button derived from validity

Do not store an `_isFormValid` bool. Derive enablement each build; disable while an async submit is in flight (from Notifier state).

```dart
final submitting = ref.watch(taskFormNotifierProvider).isLoading;
FilledButton(
  onPressed: submitting ? null : _submit, // rule 5
  child: Text(l10n.saveAction),
);
```

## Keyboard avoidance

Wrap long forms so the focused field scrolls above the keyboard: a `SingleChildScrollView` inside the body lets `Scaffold` (with `resizeToAvoidBottomInset: true`, the default) push content up. For last-field submit, ensure the submit button is reachable — put it in the scroll view or a `bottomNavigationBar`.

## Anti-patterns

- `validator: (v) async => await repo.isTaken(v)` — a validator cannot be async; the `Future` is truthy so it always "passes." Move to a Notifier (rule 4).
- Returning `'Required'` / `'Invalid email'` from a validator — un-localized; breaks every non-English locale. Use `AppLocalizations`.
- Creating a `TextEditingController`/`FocusNode` in `build()` — a fresh one every rebuild, losing text and cursor. Create in `State`, dispose in `dispose()`.
- `bool _isValid` toggled in `onChanged` to enable submit — drifts from real validity. Derive it.
- `autovalidateMode: AutovalidateMode.always` — errors shout before the user types a character.
- One `TextEditingController` listener that calls `setState` on the whole form — every keystroke rebuilds every field. Scope the rebuild.
- `debounce` timing rolled by hand with `DateTime.now()` diffs — use a `dart:async` `Timer` (deterministic under `fakeAsync`); and any timestamp the check records comes from `ref.read(clockProvider).now()`, never `DateTime.now()`.

## Definition of done

- Every controller/`FocusNode` disposed (or state lives in a Notifier); `check_forms.sh` clean.
- No string literal returned from any `validator`; all messages via `AppLocalizations`.
- No `await`/`Future` inside a sync `validator`; async checks in a debounced Notifier surfaced through `errorText`.
- `AutovalidateMode.onUserInteraction` (or an intentional submit-only choice).
- Submit enablement derived, not stored; disabled during in-flight submit.
- Each field declares `keyboardType`, `textInputAction`, and `autofillHints` where applicable; focus advances correctly.
- Errors announced via `InputDecoration` semantics, never color-only.

## Related skills

- `state-management-riverpod` — the Notifier that owns async validation and submit state.
- `async-safety` — cancel debounce timers/subscriptions on dispose; mounted guards after await.
- `i18n-rtl-l10n` — localized validator messages and labels; the non-null `AppLocalizations.of(context)` getter.
- `accessibility-as-code` — field labels, error announcement, never-color-alone, target sizes.
- `flutter-performance` — scoped rebuilds and derive-don't-store.
- `widget-composition` — small const field widgets over `_buildField` methods.
- `navigation-and-routing` — `PopScope` for unsaved-changes confirmation when leaving a dirty form.
- `service-boundary-and-native` — the Clock seam (`clockProvider`) any async check reads timestamps from.

## References

- Form: https://api.flutter.dev/flutter/widgets/Form-class.html
- TextFormField: https://api.flutter.dev/flutter/material/TextFormField-class.html
- FocusNode: https://api.flutter.dev/flutter/widgets/FocusNode-class.html
- TextInputAction: https://api.flutter.dev/flutter/services/TextInputAction.html
- Autofill: https://api.flutter.dev/flutter/services/AutofillHints-class.html
- Forms cookbook: https://docs.flutter.dev/cookbook/forms/validation
