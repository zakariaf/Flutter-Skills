// Demonstrates the native boundary: a MethodChannel quarantined to lib/native/ behind a
// thin bridge, a versioned cross-language contract owned once on the Dart side, the
// injectable gateway port features depend on, the mirror invariant (every write
// republishes), and a deterministic fake for headless tests.
//
// Neutral domain: publishing the latest Item to a home-screen widget surface. The widget
// UI itself is hand-written SwiftUI/WidgetKit or Jetpack Glance and is NOT in this file.
//
// File placement (shown in comments) is the point of the example:
//   lib/native/item_widget_bridge.dart    <- the ONLY MethodChannel owner
//   lib/native/item_widget_contract.dart  <- SOLE Dart owner of the shared format
//   lib/services/widget_gateway.dart   <- the injectable port
//   lib/native/native_widget_gateway.dart  <- the ONE live impl

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// lib/native/item_widget_contract.dart
// SOLE Dart owner of the shared format. Mirror: ItemWidgetContract.kt / .swift.
// ANY edit to a key here is an edit to those mirrors, in the SAME commit.
// A versioned file we own — NOT shared_preferences (which native code reads wrong).
// ---------------------------------------------------------------------------

const int kItemWidgetContractVersion = 1;

class ItemSnapshot {
  const ItemSnapshot({required this.title, required this.updatedAtUtc});
  final String title;
  final DateTime updatedAtUtc;

  Map<String, Object?> toContractJson() => {
        'v': kItemWidgetContractVersion,
        'title': title,
        'updatedAtUtc': updatedAtUtc.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// lib/native/item_widget_bridge.dart
// The ONLY MethodChannel construction in the app for this feature. No logic here
// beyond marshalling; nothing else may create a channel with this name.
// ---------------------------------------------------------------------------

class ItemWidgetBridge {
  const ItemWidgetBridge();
  static const _channel = MethodChannel('app/item_widget');

  Future<void> publish(Map<String, Object?>? contractJson) =>
      _channel.invokeMethod('publish', contractJson); // null clears the surface
}

// ---------------------------------------------------------------------------
// lib/services/widget_gateway.dart
// The injectable port. Features depend on THIS, never on the channel — so they
// stay channel-blind and testable with a fake.
// ---------------------------------------------------------------------------

abstract interface class WidgetGateway {
  /// Publishes [snapshot] to the native surface, or clears it when null.
  Future<void> publish(ItemSnapshot? snapshot);
}

final widgetGatewayProvider = Provider<WidgetGateway>(
  (ref) => throw UnimplementedError('override widgetGatewayProvider in main.dart'),
);

// ---------------------------------------------------------------------------
// lib/native/native_widget_gateway.dart
// The ONE live impl. Bridges the value-typed port to the contract JSON.
// ---------------------------------------------------------------------------

final class NativeWidgetGateway implements WidgetGateway {
  const NativeWidgetGateway(this._bridge);
  final ItemWidgetBridge _bridge;

  @override
  Future<void> publish(ItemSnapshot? snapshot) =>
      _bridge.publish(snapshot?.toContractJson());
}

// ---------------------------------------------------------------------------
// A repository showing the MIRROR INVARIANT: every write path that can change a
// mirrored value republishes as PART of the write — a clear republishes as hard
// as a save. Persist before publish so a crash never leaves a stale surface.
// ---------------------------------------------------------------------------

final class ItemRepository {
  ItemRepository(this._gateway);
  final WidgetGateway _gateway;

  Future<void> save(ItemSnapshot item) async {
    // await _db.transaction(() => _db.upsert(item)); // durable first (omitted)
    await _gateway.publish(item); // then the side-effect fan-out
  }

  Future<void> clear() async {
    // await _db.clear();
    await _gateway.publish(null); // the surface must not show a retracted value
  }
}

// ---------------------------------------------------------------------------
// A deterministic fake for headless tests. Records published snapshots so a test
// can assert the mirror invariant without a real channel. The REAL round-trip
// (Dart writes -> native reads) still needs an integration_test — a unit test
// asserting a fake mutated a fake proves nothing about the native read path.
// ---------------------------------------------------------------------------

final class FakeWidgetGateway implements WidgetGateway {
  final List<ItemSnapshot?> published = [];
  @override
  Future<void> publish(ItemSnapshot? snapshot) async => published.add(snapshot);
}
