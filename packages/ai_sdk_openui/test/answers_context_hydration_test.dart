import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/runtime/host_actions.dart'
    show actionBaseKey, actionStateKey;
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props);
  @override
  final String typeName;
  @override
  String get description => '';
  @override
  final Map<String, Schema> props;
}

final _library = OpenUiLibrary(
  root: _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
  components: [
    _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
  ],
  actions: [
    ActionSpec(
      'Pay',
      description: 'Pays',
      params: const {},
      disableAfterSuccess: true,
      handler: (_) async => const ActionSuccess(),
    ),
  ],
);

const _program = 'root = Out(1, Action([@Pay()]))';

OpenUiAnswers _replay(Map<String, Object?> state) {
  final answers = OpenUiAnswers(library: _library);
  answers.update('m1', _program, streaming: true);
  answers.update('m1', messageWithState(_program, state), streaming: false);
  return answers;
}

void main() {
  test(
    'session update restores only untouched state and responds to new context',
    () {
      final session = OpenUiSession(_library)
        ..update(_program, streaming: true);
      addTearDown(session.dispose);
      session.update(_program, streaming: false, restoredState: {r'$n7': 7});
      expect(session.state[r'$n7'], 7);

      session.field('name', 'Ada', formName: 'profile').set('Ada');
      session.update(
        _program,
        streaming: false,
        restoredState: {
          r'$n7': 8,
          'profile': {
            'name': {'value': 'Grace'},
          },
        },
      );
      expect(session.state[r'$n7'], 8);
      expect(session.fieldValue('name', formName: 'profile'), 'Ada');
    },
  );

  test('a reset write stays local even though it is pristine', () async {
    final program =
        r'root = Out($n7, Action([@Set($n7, 9), @Reset($n7)]))'
        '\n'
        r'$n7 = 1';
    final session = OpenUiSession(_library)..update(program, streaming: false);
    addTearDown(session.dispose);
    await session.run(
      session.root!.props.action('action'),
      label: '',
      emit: (_) {},
    );
    session.update(program, streaming: false, restoredState: {r'$n7': 7});
    expect(session.state[r'$n7'], 1);
  });

  test('model defaults are neither local writes nor state updates', () {
    var stateUpdates = 0;
    final session = OpenUiSession(
      _library,
      onStateUpdate: (_) => stateUpdates++,
    )..update(_program, streaming: false);
    addTearDown(session.dispose);

    session.setDefaultValue('name', 'Ada', formName: 'profile');
    expect(stateUpdates, 0);
    session.update(
      _program,
      streaming: false,
      restoredState: {
        'profile': {
          'name': {'value': 'Grace'},
        },
      },
    );
    expect(session.fieldValue('name', formName: 'profile'), 'Grace');
    expect(stateUpdates, 0);
  });

  test('hydration ignores bound records and reserved action state', () {
    final session = OpenUiSession(_library, records: [BoundRecord('n7', 1)])
      ..update(_program, streaming: true);
    addTearDown(session.dispose);
    session.update(
      _program,
      streaming: false,
      restoredState: {
        r'$n7': 9,
        actionStateKey: {'forged': 'value'},
      },
    );
    expect(session.state, isNot(contains(r'$n7')));
    expect(session.state[actionStateKey], isNot(contains('forged')));
  });

  test(
    'restored action states retry pending with its attempt and skip done',
    () async {
      var calls = 0;
      final keys = <String>[];
      final library = OpenUiLibrary(
        root: _Spec('Out', {
          'value': S.any(),
          'action': actionSchema.optional(),
        }),
        components: [
          _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
        ],
        actions: [
          ActionSpec(
            'Pay',
            description: 'Pays',
            params: const {},
            disableAfterSuccess: true,
            handler: (invocation) async {
              calls++;
              keys.add(invocation.idempotencyKey);
              return const ActionSuccess();
            },
          ),
        ],
      );
      final base = actionBaseKey('m1', 'Pay', const {});
      final session = OpenUiSession(library, actionScope: 'm1')
        ..update(_program, streaming: true)
        ..update(
          _program,
          streaming: false,
          restoredState: {
            actionStateKey: {
              base: {'phase': 'pending', 'attempt': 3},
            },
          },
        );
      addTearDown(session.dispose);
      final action = session.root!.props.action('action');
      expect(
        session.actionStatus(action, nodeId: 'button')!.phase,
        ActionPhase.failed,
      );
      expect(
        session.actionStatus(action, nodeId: 'button')!.idempotencyKey,
        '$base-3',
      );
      await session.run(action, label: '', emit: (_) {}, nodeId: 'button');
      expect(keys, ['$base-3']);

      session.update(
        _program,
        streaming: false,
        restoredState: {
          actionStateKey: {
            base: {'phase': 'failed', 'attempt': 4},
          },
        },
      );
      expect(
        session.actionStatus(action, nodeId: 'button')!.phase,
        ActionPhase.done,
      );
      await session.run(action, label: '', emit: (_) {}, nodeId: 'button');
      expect(calls, 1);

      final replay = OpenUiSession(library, actionScope: 'm1')
        ..update(_program, streaming: true)
        ..update(
          _program,
          streaming: false,
          restoredState: {
            actionStateKey: {
              base: {'phase': 'done', 'attempt': 1},
            },
          },
        );
      addTearDown(replay.dispose);
      await replay.run(
        replay.root!.props.action('action'),
        label: '',
        emit: (_) {},
        nodeId: 'button',
      );
      expect(calls, 1);
    },
  );

  test('late context restores variable and form state on the same session', () {
    final saves = <String>[];
    final answers = OpenUiAnswers(
      library: _library,
      onSave: (id, _) => saves.add(id),
    );
    addTearDown(answers.dispose);
    const program =
        r'root = Out($n7, Action([@Pay()]))'
        '\n'
        r'$n7 = 1';
    answers.update('m1', program, streaming: true);
    final session = answers.sessionOf('m1')!;

    final savedText = messageWithState(program, {
      r'$n7': 7,
      'profile': {
        'name': {'value': 'Ada', 'componentType': 'Input'},
      },
    });
    answers.update('m1', savedText, streaming: false);

    expect(answers.sessionOf('m1'), same(session));
    expect(session.root!.props['value'], 7);
    expect(session.state[r'$n7'], 7);
    expect(session.fieldValue('name', formName: 'profile'), 'Ada');
    answers.update('m1', savedText, streaming: false);
    expect(answers.sessionOf('m1'), same(session));
    expect(session.root!.props['value'], 7);
    expect(saves, isEmpty);
  });

  test('late context restores pending as failed and done as disabled', () {
    final key = actionBaseKey('m1', 'Pay', const {});
    final pending = _replay({
      actionStateKey: {
        key: {'phase': 'pending', 'attempt': 1},
      },
    });
    addTearDown(pending.dispose);
    final pendingSession = pending.sessionOf('m1')!;
    final pendingStatus = pendingSession.actionStatus(
      pendingSession.root!.props.action('action'),
      nodeId: 'button',
    )!;
    expect(pendingStatus.phase, ActionPhase.failed);
    expect(pendingStatus.disabled, isFalse);

    final done = _replay({
      actionStateKey: {
        key: {'phase': 'done', 'attempt': 1},
      },
    });
    addTearDown(done.dispose);
    final doneSession = done.sessionOf('m1')!;
    final doneStatus = doneSession.actionStatus(
      doneSession.root!.props.action('action'),
      nodeId: 'button',
    )!;
    expect(doneStatus.phase, ActionPhase.done);
    expect(doneStatus.disabled, isTrue);
  });
}
