# Reference — the grep-based invariant gate

A policy/grep gate scans source or config and fails the build when a banned string
appears (or a required one is missing). Each is ~10 lines. Each exists because a
single line — one import, one attribute, one literal — silently defeats a contract
that no analyzer rule, no type, and no widget test can see. Author them as a Dart
test under `test/policy/` (runs with the suite) or as a shell step in the workflow
(runs even when the Dart suite is broken). Same discipline either way.

## The three-criteria bar

All three, or it does not belong here. Two out of three means code review.

| Criterion | Meaning |
|---|---|
| **Textually decidable** | Provable by reading source or config. If it needs a running app, it is a widget or device test. |
| **Silent when broken** | The app builds, the suite is green, and the user (or a data-loss) is the only signal. Nothing in review or the type system catches it. |
| **One line to break** | The failure is a plausible copy-paste, a merge, or a 2am "cleanup" — not a rewrite. |

Everything else is taste, and taste does not earn a grep. Banning a widget modifier
or a `default:` on a sealed type by string match produces false positives that get
the whole directory deleted the first time someone is in a hurry. **A gate that
cries wolf is worse than no gate.** Package bans that are about architecture, not
silent failure (`provider`, `go_router`, a state library) belong in a pubspec/dep
review — they cannot ship a silent defect, and every entry here is a promise the
gate must keep forever.

## Strip comments first — always

Every one of these searches for a string that is *also* what a developer types when
explaining why the string is banned. A raw grep fails the moment someone writes
`// never use HttpClient here`. Strip comments before matching.

```dart
// test/policy/policy_support.dart
import 'dart:io';

final _block = RegExp(r'/\*.*?\*/', dotAll: true);
final _line = RegExp(r'//[^\n]*');
final _xml = RegExp(r'<!--.*?-->', dotAll: true);

/// Dart source with comments removed, so a rule's own explanation cannot trip it.
/// Caveat: this also eats `//` inside string literals — never write a policy
/// gate whose needle can legitimately appear inside a URL-shaped string.
String codeOf(File f) =>
    f.readAsStringSync().replaceAll(_block, '').replaceAll(_line, '');

String xmlOf(File f) => f.readAsStringSync().replaceAll(_xml, '');

/// Generated output is excluded: nobody hand-edits it, and scanning it only
/// invites false positives on code nobody wrote.
Iterable<File> dartFilesIn(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
```

`flutter test` sets the working directory to the package root, so relative paths
(`lib`, `android/app/src/main/AndroidManifest.xml`) resolve. Never build a path from
`Platform.script`.

## Anchor the needle to a structure, never a bare whole-file `contains`

- **A banned import** → match the import *URI* on an `import` line, not the text `http`
  (which hits `https://` in a doc comment and every `Uri` in a string).
- **A required manifest attribute** → assert it inside the right *element*. The same
  intent string in a stray `<intent-filter>` instead of `<queries>` grants nothing but
  makes a whole-file `contains` pass green while the app misbehaves.
- **A schema invariant** (e.g. a composite primary key) → scope the regex to the *class
  body* of the table you mean. Every other table legitimately has a surrogate id, so a
  file-wide search would be permanently red.
- **A literal you must forbid** → scan line-wise so the failure carries a line number,
  and normalize (`toUpperCase()`, strip `_` digit separators) so `0xFF_FF` and `0xffff`
  don't slip past.

## Accumulate all offenders; fail once

A test that `expect`s inside the loop reports offender #1 and hides the other four.
Collect every path (and line, where relevant), then one assertion at the end.

```dart
final offenders = <String>[];
for (final f in dartFilesIn('lib')) {
  // ... add '${f.path}: <detail>' for each hit ...
}
expect(offenders, isEmpty, reason: '<why this matters>\n${offenders.join('\n')}');
```

## Write the reason for a stranger at 2am

The person reading the failure is deciding whether to fix the code or delete the
gate. Name the **consequence to the user or the data**, not the rule. "Fails the
import check" gets deleted; "these imports break the no-network promise this audience
verifies adversarially" does not. Put the same argument as a doc comment *at the point
of temptation* — in the manifest, in the table file — because the person about to
break the rule is standing there, not in `test/policy/`.

## A worked example — a required manifest attribute

```dart
// test/policy/manifest_policy_test.dart
import 'dart:io';
import 'package:test/test.dart';
import 'policy_support.dart';

void main() {
  final xml = xmlOf(File('android/app/src/main/AndroidManifest.xml'));

  test('auto-backup is disabled', () {
    expect(
      xml,
      contains('android:allowBackup="false"'),
      reason: 'android:allowBackup defaults to TRUE. Left alone, the OS uploads '
          'the app database to the user\'s cloud backup — every record they own. '
          'If the app promises on-device-only, this contradicts it silently.',
    );
  });
}
```

## Adding a new one — the checklist

1. Check it against the three criteria. Two of three → code review.
2. New file in `test/policy/` (or a step in the workflow), named for the invariant.
3. Anchor the needle to a structure — import URI, class body, XML element, line.
4. Read through `codeOf`/`xmlOf` so the rule's own docs can't fail the rule.
5. Accumulate offenders; one `expect` at the end with every path and line.
6. Write the `reason` for a stranger; name the consequence to the person using the app.
7. Put the same argument as a comment at the point of temptation.
