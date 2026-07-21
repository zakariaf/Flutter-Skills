# Test patterns by layer

Each layer has a fixed harness, import set, teardown, and edge-case checklist. Pick the
layer by the code under test, then follow its row.

## Layer summary

| Layer | Runner | Binding | Doubles | Key teardown |
|---|---|---|---|---|
| Pure domain (Flutter-free package) | `dart test` | none | none — construct real values | none |
| Value conversion / math | `dart test` | none | none | none |
| Data (Drift) | `flutter test` | none | real `NativeDatabase.memory()` | `db.close()` |
| Notifier / ViewModel | `flutter test` | none | `ProviderContainer` + fakes | `container.dispose()` |
| Service gateway / port | `flutter test` | none | bare-`implements` fake | fake resets itself |
| Widget | `flutter test` | `TestWidgetsFlutterBinding` | fakes via overrides | pump, not settle |
| Integration | `integration_test` | `IntegrationTestWidgetsFlutterBinding` | real stack | device-only |

## Pure domain

- No `flutter_test` import; the package declares no Flutter SDK constraint so the ban
  is structural, not just linted.
- Construct real value objects as literals; there is nothing to fake.
- Inject `Clock` and any RNG seed as constructor arguments so the test needs no
  clock/entropy fakery beyond `withClock`/a fixed `Random(seed)`.
- Table-driven: one `test()` per named case in a `cases` list; arrange-act-assert; a
  descriptive name that states the behaviour.

Edge cases to always cover: empty input, single element, the boundary/half-way rounding
value, the negative/zero case, and the largest realistic magnitude.

## Data layer (Drift)

- `AppDatabase(NativeDatabase.memory())` in `setUp`; `addTearDown(db.close)`.
- Set the connection to close streams synchronously so `.watch()` subscriptions do not
  leak "Timer still pending" between tests.
- Assert the **real** schema invariants: a `CHECK`/`NOT NULL`/`FOREIGN KEY` violation
  throws `SqliteException`; a `.watch()` stream emits the expected sequence after a
  mutation; a transaction rolls back atomically on failure.
- Never substitute a mocked DAO — it proves nothing about SQL, indexes, or migrations.
  Mock repositories only *above* the data layer.
- If the production DB is encrypted, test business logic on a plain in-memory DB and
  keep keying/cipher-header assertions to a separate keyed-**file** suite;
  `NativeDatabase.memory` cannot open a keyed DB.

Edge cases: constraint rejection, unique-index collision, cascade delete, empty-table
query, `.watch()` emission ordering, transaction rollback.

## Notifier / ViewModel (headless)

```dart
final container = ProviderContainer(
  overrides: [repositoryProvider.overrideWith((ref) => _FakeRepo())],
);
addTearDown(container.dispose);

// Await the first async build, then drive intents through `.notifier`.
await container.read(taskListProvider.future);
await container.read(taskListProvider.notifier).add(_aTask);
expect(container.read(taskListProvider), isA<AsyncData<List<Task>>>());
```

- Never pump a widget to test state — the container is faster and isolates the layer.
- `container.listen(provider, (prev, next) {...}, fireImmediately: true)` to assert the
  emission sequence, not just the final value.
- Riverpod 3.x `ProviderContainer.test()` auto-disposes and pumps the microtask queue;
  prefer it when available.

Edge cases: initial loading state, error state (`AsyncError`), rapid successive
intents, a `family` argument, an `autoDispose` provider tearing down on last listener.

## Service gateway / port

- The port is an abstract interface (`abstract interface class NotificationGateway`);
  the live impl wraps the plugin/native channel; tests use a **bare-`implements`
  fake** that honours the contract (see `references/property-and-fakes.md`).
- Quarantine any raw `MethodChannel` mock to a single channel-contract file whose only
  job is to pin the plugin's wire behaviour so an upgrade fails loudly. A channel
  contract test needs `TestWidgetsFlutterBinding.ensureInitialized()` at the top of
  `main()` and `tearDown(() => messenger.setMockMethodCallHandler(channel, null))` to
  avoid an order-dependent flake. Nothing else belongs there.

## Widget

Owned by `widget-golden-and-a11y-testing`; two rules bleed down into every layer:

- Override the defaults explicitly — `locale`, `TextDirection`, `textScaler`, surface
  size. The 800x600 / `1.0` / `en` / LTR defaults hide RTL and dynamic-type bugs.
- `pump(Duration)`, never `pumpAndSettle()`, on any screen with an indefinite
  animation.

## Integration

- Reserve `integration_test` for the few make-or-break end-to-end journeys; keep the
  count in single digits. Anything a widget test can assert belongs in a widget test,
  where it runs in milliseconds with a readable failure.
- One emulator samples **zero** device diversity and cannot exercise real native
  side-effects — do not mistake an integration suite for coverage of the risk classes
  (OEM variance, real audio, real permissions) it cannot reach. Those go to the manual
  pass.
