// Async field validation done correctly: OUT of the sync validator, in a
// manual Riverpod AsyncNotifier that debounces keystrokes with a dart:async
// Timer (deterministic under fakeAsync), runs the availability check through a
// repository, ignores stale results, cancels its timer on dispose, and surfaces
// the outcome as AsyncValue that the TextFormField reads via errorText. Any
// timestamp the check records comes from clockProvider.now(), not DateTime.now().
//
// Domain: checking whether an Account name is already taken.

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';

enum NameCheck { available, taken }

// clockProvider is defined once app-wide (D3); shown here for context.
final clockProvider = Provider<Clock>((ref) => const Clock());

// The shared repository read path (owned by lib/data/); injected here.
abstract interface class AccountRepository {
  Future<bool> isNameTaken(String name);
}
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => throw UnimplementedError('override in bootstrap'),
);

// Debounce window is a structural timing constant, not a design token.
const _debounce = Duration(milliseconds: 400);

// Manual AsyncNotifierProvider (D7). State is idle (null) or a NameCheck result.
final nameAvailabilityNotifierProvider =
    AsyncNotifierProvider.autoDispose<NameAvailabilityNotifier, NameCheck?>(
  NameAvailabilityNotifier.new,
);

// Riverpod 3.0: the base class is the unified AsyncNotifier; auto-dispose is the
// provider modifier above (.autoDispose), not a separate base class.
class NameAvailabilityNotifier extends AsyncNotifier<NameCheck?> {
  Timer? _timer;
  String _query = '';

  @override
  FutureOr<NameCheck?> build() {
    // Cancel any pending debounce when the notifier is disposed (async-safety).
    ref.onDispose(() => _timer?.cancel());
    return null; // idle: no check attempted yet.
  }

  void onNameChanged(String raw) {
    final name = raw.trim();
    _query = name;
    _timer?.cancel();

    if (name.isEmpty) {
      state = const AsyncData(null); // back to idle
      return;
    }

    // Debounce with a Timer; deterministic in tests under fakeAsync. Any
    // timestamp the check records comes from ref.read(clockProvider).now() (D3),
    // never DateTime.now().
    _timer = Timer(_debounce, () => _run(name));
  }

  Future<void> _run(String name) async {
    // Capture the settled value BEFORE entering loading; keep it visible during
    // the check via copyWithPrevious so a superseded result can restore it.
    final previous = state.valueOrNull;
    state = const AsyncLoading<NameCheck?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final taken = await ref.read(accountRepositoryProvider).isNameTaken(name);
      // Staleness guard: a newer keystroke superseded this check — restore the
      // prior settled value rather than publishing a stale answer.
      if (name != _query) return previous;
      return taken ? NameCheck.taken : NameCheck.available;
    });
  }
}

// The field reads notifier state and maps it to errorText. Loading is NOT an
// error; a failed check is distinct from "taken".
class AccountNameField extends ConsumerStatefulWidget {
  const AccountNameField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  ConsumerState<AccountNameField> createState() => _AccountNameFieldState();
}

class _AccountNameFieldState extends ConsumerState<AccountNameField> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(nameAvailabilityNotifierProvider);

    return TextFormField(
      controller: widget.controller,
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.none,
      autofillHints: const [AutofillHints.newUsername],
      onChanged:
          ref.read(nameAvailabilityNotifierProvider.notifier).onNameChanged,
      // Sync validator stays pure: shape only. Async result comes via errorText.
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? l10n.fieldRequired : null,
      decoration: InputDecoration(
        labelText: l10n.accountNameLabel,
        suffixIcon: status.isLoading
            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator())
            : null,
        errorText: switch (status) {
          AsyncData(:final value) when value == NameCheck.taken => l10n.nameTaken,
          AsyncError() => l10n.nameCheckFailed,
          _ => null, // idle / loading / available
        },
      ),
    );
  }
}
