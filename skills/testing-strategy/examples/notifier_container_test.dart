// Demonstrates: testing a Riverpod 3.x AsyncNotifier ViewModel HEADLESSLY with a
// ProviderContainer and dependency overrides — no widget pumped. A bare-`implements`
// fake stands in for the owned repository (driven by an enum so each failure
// environment is a named, compile-checked case), and the test asserts on AsyncValue
// and the emission sequence. Requires `flutter test` and flutter_riverpod.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/result.dart'; // sealed Result<T, F extends Failure> (Ok/Err)
import 'package:app/data/task_repository.dart'; // shared data layer
import 'package:app/features/tasks/domain/task.dart';
import 'package:app/features/tasks/presentation/task_list_notifier.dart';

// --- an owned collaborator faked with bare `implements`, state driven by an enum ---

enum RepoEnv { healthy, writeRejected }

class FakeTaskRepository implements TaskRepository {
  FakeTaskRepository(this.env);
  final RepoEnv env;
  final _store = <Task>[];

  @override
  Future<List<Task>> load() async => List.unmodifiable(_store);

  @override
  Future<Result<void, TaskFailure>> add(Task task) async {
    switch (env) {
      // No `default:` — a new RepoEnv value is a compile error until handled here.
      case RepoEnv.healthy:
        _store.add(task);
        return const Ok(null);
      case RepoEnv.writeRejected:
        return const Err(TaskFailure.writeRejected());
    }
  }
}

void main() {
  const aTask = Task(id: '1', title: 'Draft the report');

  ProviderContainer makeContainer(RepoEnv env) {
    final container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWith((ref) => FakeTaskRepository(env)),
      ],
    );
    addTearDown(container.dispose); // dispose so autoDispose + streams tear down
    return container;
  }

  test('initial build resolves to an empty AsyncData list', () async {
    final container = makeContainer(RepoEnv.healthy);
    final tasks = await container.read(taskListProvider.future);
    expect(tasks, isEmpty);
  });

  test('add publishes the new task through AsyncData', () async {
    final container = makeContainer(RepoEnv.healthy);
    await container.read(taskListProvider.future);

    await container.read(taskListProvider.notifier).add(aTask);

    final state = container.read(taskListProvider);
    expect(state, isA<AsyncData<List<Task>>>());
    expect(state.requireValue.single.title, 'Draft the report');
  });

  test('a rejected write surfaces a typed failure and leaves state unchanged', () async {
    final container = makeContainer(RepoEnv.writeRejected);
    await container.read(taskListProvider.future);

    final result = await container.read(taskListProvider.notifier).add(aTask);

    expect(result, isA<Err<void, TaskFailure>>()); // the failure is surfaced, not swallowed
    expect(container.read(taskListProvider).requireValue, isEmpty);
  });

  test('listen observes the loading -> data emission sequence', () async {
    final container = makeContainer(RepoEnv.healthy);
    final states = <AsyncValue<List<Task>>>[];
    container.listen(taskListProvider, (_, next) => states.add(next),
        fireImmediately: true);

    await container.read(taskListProvider.future);

    expect(states.first, isA<AsyncLoading<List<Task>>>());
    expect(states.last, isA<AsyncData<List<Task>>>());
  });
}
