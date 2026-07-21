// A complete grep-based invariant gate for a single-package Flutter app.
//
// Demonstrates the whole technique in one file:
//   - strip comments before matching (a rule's own explanation contains its needle)
//   - anchor each needle to a STRUCTURE (an import URI, an XML element) not raw text
//   - accumulate every offender and fail ONCE with the full list
//   - write the reason for a stranger at 2am, naming the consequence to the user
//
// These are pure Dart: they import `package:test/test.dart`, not `flutter_test`,
// but run with the rest of the suite via `flutter test test/policy`.
// `flutter test` sets the working directory to the package root, so the relative
// paths below resolve. Never build a path from `Platform.script`.

import 'dart:io';

import 'package:test/test.dart';

// --- support: comment stripping + file discovery ---------------------------

final RegExp _block = RegExp(r'/\*.*?\*/', dotAll: true);
final RegExp _line = RegExp(r'//[^\n]*');
final RegExp _xmlComment = RegExp(r'<!--.*?-->', dotAll: true);

/// Dart source with comments removed, so a rule's own explanation cannot trip it.
/// Caveat: this also eats `//` inside string literals — never write a policy
/// gate whose needle can legitimately appear inside a URL-shaped string.
String _codeOf(File f) =>
    f.readAsStringSync().replaceAll(_block, '').replaceAll(_line, '');

String _xmlOf(File f) => f.readAsStringSync().replaceAll(_xmlComment, '');

/// Generated output is excluded: nobody hand-edits it, and scanning it only
/// invites false positives on code nobody wrote.
Iterable<File> _dartFilesIn(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));

// --- gate 1: banned imports (match the import URI, not the file) -----------

void main() {
  test('lib/ imports nothing that can reach the network or phone home', () {
    // Architecture-only bans (a state library, a router) do NOT belong here —
    // they cannot ship a silent defect. Every entry is a promise kept forever.
    const List<String> banned = <String>[
      'package:http/',
      'package:dio/',
      'package:web_socket_channel/',
      'package:firebase_core/',
      'package:firebase_crashlytics/',
      'package:sentry_flutter/',
    ];
    final RegExp importUri =
        RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);

    final List<String> offenders = <String>[];
    for (final File f in _dartFilesIn('lib')) {
      final String code = _codeOf(f);
      for (final Match m in importUri.allMatches(code)) {
        final String uri = m.group(1)!;
        if (banned.any(uri.startsWith)) offenders.add('${f.path}: $uri');
      }
      // dart:io is NOT banned (file paths need it); name the one symbol with no
      // legitimate use here instead of banning the whole library.
      if (code.contains('HttpClient')) offenders.add('${f.path}: HttpClient');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'No network, no analytics, no crash reporter — that is the '
          'product, not a preference. A crash reporter is the tempting one: it '
          'looks like the fix for having no field signal. It is not; the crash '
          'log stays on-device and is exported by the user.\n'
          '${offenders.join('\n')}',
    );
  });

  // --- gate 2: a required manifest attribute (anchored to the element) ------

  test('auto-backup is disabled in the Android manifest', () {
    final String xml =
        _xmlOf(File('android/app/src/main/AndroidManifest.xml'));

    expect(
      xml,
      contains('android:allowBackup="false"'),
      reason: 'android:allowBackup defaults to TRUE. Left alone, the OS uploads '
          'the SQLite database — every record the user owns — to their cloud '
          'backup, contradicting the on-device-only promise. Restore is a '
          'deliberate, user-initiated export instead.',
    );
  });

  // --- gate 3: a text-scale escape hatch that silently defeats a11y ----------

  test('lib/ never clamps the text scaler', () {
    // Clamping is the one-line "fix" a contributor reaches for when an overflow
    // test goes red; it silently defeats the whole large-text accessibility
    // matrix while contrast and tap-target checks still pass.
    const List<String> banned = <String>[
      'withClampedTextScaling',
      'textScaleFactor',
    ];

    final List<String> offenders = <String>[];
    for (final File f in _dartFilesIn('lib')) {
      final String code = _codeOf(f);
      for (final String needle in banned) {
        if (code.contains(needle)) offenders.add('${f.path}: $needle');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Clamping text scale makes large-text users unreadable while every '
          'automated check stays green. Fix the layout to fit the text, never '
          'the other way round.\n${offenders.join('\n')}',
    );
  });
}
