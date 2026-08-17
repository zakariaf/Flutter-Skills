// Demonstrates a generator whose output is a pure function of an injected civil-date key:
// FNV-1a-64 + a SplitMix64 mix step feeding a PRNG the repo owns, per-feature salts, a
// frozen draw order, a canonical serialization to fingerprint, and a versioned cutover that
// keeps history reproducible.
//
// Pure Dart on purpose — no Flutter, no dart:io, no clock, no ambient Random. That is what
// makes scripts/check-determinism-bans.sh a real gate over this directory.
//
// Note: 64-bit wrap-around arithmetic below is VM/AOT semantics. On the web `int` is a JS
// double and these values differ — see references/seed-derivation.md.

import 'dart:convert';

// ── Hashing and the PRNG ─────────────────────────────────────────────────────

/// FNV-1a-64 over the UTF-8 bytes of [key]. Specified, tiny, portable — chosen so
/// the derivation can be reimplemented anywhere and checked against this one.
int fnv1a64(String key) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(key)) {
    hash = (hash ^ byte) * 0x100000001b3; // 64-bit wrap-around is intended
  }
  return hash;
}

/// SplitMix64. Eight lines, published test vectors, and ours forever — unlike
/// `dart:math`'s Random, whose algorithm carries no cross-version guarantee.
class SeededRng {
  SeededRng(this._state);

  int _state;

  int nextInt64() {
    _state += 0x9e3779b97f4a7c15;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xbf58476d1ce4e5b9;
    z = (z ^ (z >>> 27)) * 0x94d049bb133111eb;
    return z ^ (z >>> 31);
  }

  /// Uniform in `[0, max)`. Every draw advances the one stream: the ORDER of
  /// draws is part of the contract, so never reorder calls during a refactor.
  int nextInt(int max) => nextInt64().toUnsigned(63) % max;
}

/// Frozen per-feature salts. Two features seeded from the same day must not draw
/// the same sequence, or their output visibly moves together. Never change one
/// after shipping — that is a version cutover, not a tweak.
abstract final class Salts {
  static const int dailyPick = 0x5049_434B_0001;
  static const int featuredBanner = 0x4241_4E52_0001;
}

/// The ONLY place the calendar meets the generator. [isoDay] is a civil date
/// ("2026-07-04") supplied by the caller — nothing here reads a clock.
SeededRng seedFor(String isoDay, {required int featureSalt, int modeSalt = 0}) =>
    SeededRng(fnv1a64(isoDay) ^ featureSalt ^ modeSalt);

// ── The generated artifact ───────────────────────────────────────────────────

class Item {
  const Item(this.id, this.name);
  final int id;
  final String name;
}

/// Stand-in for whatever catalog the app draws from. Order is explicit and
/// stable — never iterate a Set or sort by hashCode before drawing.
const catalog = <Item>[
  Item(1, 'alpha'), Item(2, 'bravo'), Item(3, 'charlie'), Item(4, 'delta'),
  Item(5, 'echo'), Item(6, 'foxtrot'), Item(7, 'golf'), Item(8, 'hotel'),
];

class DailyPick {
  const DailyPick({
    required this.isoDay,
    required this.items,
    required this.generatorVersion,
  });

  final String isoDay;
  final List<Item> items;
  final int generatorVersion;

  /// Canonical serialization: fixed field order, integer ids, no doubles, no
  /// collection iteration order. `toString()` would not be canonical.
  String canonical() =>
      'v$generatorVersion|$isoDay|${items.map((i) => i.id).join(',')}';

  /// What the golden vector table stores — one line, so a diff is reviewable.
  int fingerprint() => fnv1a64(canonical());
}

// ── Versioning: a shipped generator is frozen ────────────────────────────────

const int currentGeneratorVersion = 2;

/// v2 improved the selection; days BEFORE the cutover must still reproduce
/// exactly what their users saw, so v1 stays in the binary forever.
const String v2CutoverDay = '2026-09-01';

DailyPick generateDailyPick(String isoDay) =>
    isoDay.compareTo(v2CutoverDay) < 0 ? _generateV1(isoDay) : _generateV2(isoDay);

DailyPick _generateV1(String isoDay) {
  final rng = seedFor(isoDay, featureSalt: Salts.dailyPick);
  final remaining = [...catalog];
  final picked = <Item>[];
  for (var i = 0; i < 3; i++) {
    picked.add(remaining.removeAt(rng.nextInt(remaining.length)));
  }
  return DailyPick(isoDay: isoDay, items: picked, generatorVersion: 1);
}

DailyPick _generateV2(String isoDay) {
  final rng = seedFor(isoDay, featureSalt: Salts.dailyPick, modeSalt: 2);
  final remaining = [...catalog];
  final picked = <Item>[];
  // v2 draws a size first, THEN the items. Adding that draw is exactly why this
  // had to be a new version: it shifts every subsequent draw.
  final size = 3 + rng.nextInt(2);
  for (var i = 0; i < size; i++) {
    picked.add(remaining.removeAt(rng.nextInt(remaining.length)));
  }
  return DailyPick(isoDay: isoDay, items: picked, generatorVersion: 2);
}

// ── Labels are a frozen threshold table over a measured metric ───────────────

enum PickSize { small, medium, large }

/// Measured, then labeled. Monotonic by construction, and asserted to stay that
/// way — a label is a calibration, never a proof, and never re-run on shipped
/// content.
PickSize labelFor(int itemCount) => switch (itemCount) {
      <= 3 => PickSize.small,
      == 4 => PickSize.medium,
      _ => PickSize.large,
    };
