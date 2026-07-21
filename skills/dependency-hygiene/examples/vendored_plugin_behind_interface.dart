// Demonstrates the vendoring seam: the app depends only on an interface, so a
// bus-factor-1 native plugin can be swapped for a vendored copy (path: dep in
// pubspec) without a single line in lib/ moving. Also shows the deterministic
// fake the interface enables in tests. Generic domain: on-device secure storage.
//
// This file is illustrative; the `some_secure_storage` package is a stand-in for
// whatever single-maintainer native plugin your app cannot build without.

import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- The port the whole app depends on ------------------------------------
// Every call site and every test references this type, never the plugin.

abstract interface class SecureStorageGateway {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

// --- The single thin live implementation ----------------------------------
// The ONLY file in the app where the plugin's package name appears. When the
// plugin is vendored into third_party/ and the pubspec repoints via `path:`,
// this file does not change — the import path stays identical.

// import 'package:some_secure_storage/some_secure_storage.dart';
// (imagined API: SomeSecureStorage().put/get/remove)

class PluginSecureStorageGateway implements SecureStorageGateway {
  PluginSecureStorageGateway(this._plugin);

  // Typed as the plugin's client; shown as `Object` here to keep the example
  // self-contained without the real package.
  final Object _plugin;

  @override
  Future<void> write(String key, String value) async {
    // await (_plugin as SomeSecureStorage).put(key, value);
  }

  @override
  Future<String?> read(String key) async {
    // return (_plugin as SomeSecureStorage).get(key);
    return null;
  }

  @override
  Future<void> delete(String key) async {
    // await (_plugin as SomeSecureStorage).remove(key);
  }
}

// --- Provider-as-DI: throws until the composition root overrides it --------
// The live impl is bound once at startup for the real app; tests override with
// the fake below. Nothing downstream knows which is in play.

final secureStorageGatewayProvider = Provider<SecureStorageGateway>((ref) {
  throw UnimplementedError(
    'Override secureStorageGatewayProvider at the composition root '
    'with PluginSecureStorageGateway(...) or a fake.',
  );
});

// --- The deterministic fake the interface buys you in tests ---------------
// Owned code: a fake, not a mock. No plugin, no platform channel, no I/O.

class FakeSecureStorageGateway implements SecureStorageGateway {
  final Map<String, String> _store = {};

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

// Example wiring in a test:
//
//   final container = ProviderContainer(overrides: [
//     secureStorageGatewayProvider.overrideWithValue(FakeSecureStorageGateway()),
//   ]);
//
// The whole point: the day the plugin breaks and you vendor it into
// third_party/, only PluginSecureStorageGateway and the pubspec change. The
// interface, the provider, every call site, and this fake stay exactly as-is.
