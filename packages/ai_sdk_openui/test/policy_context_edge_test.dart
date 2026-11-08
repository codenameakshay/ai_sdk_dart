import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

final class _Restricted implements ComponentSpec {
  const _Restricted();
  @override
  String get typeName => 'Restricted';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {'action': Steps.openUrl};
}

void main() {
  const payload = {'type': 'open_url', 'url': 'https://example.com'};
  test('cyclic state member action validation terminates', () {
    const source =
        r'$record = {selected: $record.selected}'
        '\n'
        r'root = Col([Button("Go", $record.selected)])';
    final report = intelligentUi.validate(
      source,
      policy: const ValidationPolicy(allowedActions: {}),
    );
    expect(report.hasRoot, isTrue);
    expect(report.nodes, 2);
    expect(report.depth, 2);
    expect(report.statements, 2);
    expect(report.issues, isEmpty);
  });
  for (final path in ['.selected', '["selected"]']) {
    test('literal state action member obeys allow list: $path', () async {
      final source =
          r'$record = {selected: {type: "open_url", url: "https://example.com"}}'
          '\n'
          'root = Col([Button("Go", \$record$path)])';
      final session = OpenUiSession(intelligentUi)
        ..update(source, streaming: false);
      addTearDown(session.dispose);
      final events = <ActionEvent>[];
      await session.run(
        session.root!.props.elements('children').single.props.action('action'),
        label: 'Go',
        emit: events.add,
      );
      expect(events, hasLength(1));
      expect(events.single.type, ActionEvent.openUrl);
      expect(events.single.params, {'url': 'https://example.com'});
      final report = intelligentUi.validate(
        source,
        policy: const ValidationPolicy(allowedActions: {}),
      );
      expect(report.ok, isFalse);
      expect(report.issues.map((i) => i.code), contains('action-not-allowed'));
    });
  }
  test('literal object action member obeys allow list', () async {
    const source =
        'root = Col([Button("Go", {selected: {type: "open_url", url: "https://example.com"}}.selected)])';
    final session = OpenUiSession(intelligentUi)
      ..update(source, streaming: false);
    addTearDown(session.dispose);
    final events = <ActionEvent>[];
    await session.run(
      session.root!.props.elements('children').single.props.action('action'),
      label: 'Go',
      emit: events.add,
    );
    expect(events, hasLength(1));
    expect(events.single.type, ActionEvent.openUrl);
    expect(events.single.params, {'url': 'https://example.com'});
    final report = intelligentUi.validate(
      source,
      policy: const ValidationPolicy(allowedActions: {}),
    );
    expect(report.ok, isFalse);
    expect(report.issues.map((i) => i.code), contains('action-not-allowed'));
  });
  for (final expression in [
    '@ToAssistant("Help", {type: "open_url", url: "https://example.com"})',
    'Action([@ToAssistant("Help", {type: "open_url", url: "https://example.com"})])',
  ]) {
    test('passive assistant context is not an action: $expression', () async {
      final source = 'root = Col([Button("Go", $expression)])';
      final session = OpenUiSession(intelligentUi)
        ..update(source, streaming: false);
      addTearDown(session.dispose);
      final events = <ActionEvent>[];
      await session.run(
        session.root!.props.elements('children').single.props.action('action'),
        label: 'Go',
        emit: events.add,
      );
      expect(events, hasLength(1));
      expect(events.single.type, ActionEvent.continueConversation);
      expect(events.single.params, {'context': payload});
      final report = intelligentUi.validate(
        source,
        policy: const ValidationPolicy(allowedActions: {'ToAssistant'}),
      );
      expect(report.issues.map((i) => i.toJson()), isEmpty);
      expect(report.ok, isTrue);
    });
  }

  test('state action scanning does not count passive payload twice', () {
    const source =
        r'$action = @ToAssistant("Help", {data: "123456789"})'
        '\n'
        r'root = Col([Button("Go", $action)])';
    final report = intelligentUi.validate(
      source,
      policy: const ValidationPolicy(maxStringLength: 8),
    );
    expect(
      report.issues.where((i) => i.code == 'string-too-long'),
      hasLength(1),
    );
  });

  test(
    'state action scanning does not count passive component nodes twice',
    () {
      const source =
          r'$action = @ToAssistant("Help", Card([Title("Hi")]))'
          '\n'
          r'root = Col([Button("Go", $action)])';
      final report = intelligentUi.validate(
        source,
        policy: const ValidationPolicy(maxNodes: 4),
      );
      expect(report.nodes, 4);
      expect(report.ok, isTrue);
    },
  );

  test('legacy step plan emits one allow-list issue per rejected step', () {
    final report = intelligentUi.validate(
      'root = Col([Button("Go", {steps: [{type: "open_url", url: "x"}]} )])',
      policy: const ValidationPolicy(allowedActions: {}),
    );
    expect(
      report.issues.where((i) => i.code == 'action-not-allowed'),
      hasLength(1),
    );
  });

  test('nested legacy plan is passive step data', () async {
    const source =
        'root = Col([Button("Go", {steps: [{steps: '
        '[{type: "open_url", url: "https://example.com"}]}]})])';
    final session = OpenUiSession(intelligentUi)
      ..update(source, streaming: false);
    addTearDown(session.dispose);
    final events = <ActionEvent>[];
    await session.run(
      session.root!.props.elements('children').single.props.action('action'),
      label: 'Go',
      emit: events.add,
    );
    expect(events, isEmpty);
    final report = intelligentUi.validate(
      source,
      policy: const ValidationPolicy(allowedActions: {}),
    );
    expect(report.ok, isTrue);
    expect(report.issues, isEmpty);
  });

  test('legacy action AST honors last duplicate type key', () async {
    const source =
        'root = Col([@Each([1], "it", Button("Go", '
        '{type: "continue_conversation", type: "open_url", url: "https://example.com"}))])';
    final session = OpenUiSession(intelligentUi)
      ..update(source, streaming: false);
    addTearDown(session.dispose);
    final events = <ActionEvent>[];
    await session.run(
      session.root!.props.elements('children').single.props.action('action'),
      label: 'Go',
      emit: events.add,
    );
    expect(events, hasLength(1));
    expect(events.single.type, ActionEvent.openUrl);
    expect(events.single.params, {'url': 'https://example.com'});
    final report = intelligentUi.validate(
      source,
      policy: const ValidationPolicy(allowedActions: {'ToAssistant'}),
    );
    expect(report.ok, isFalse);
    expect(report.issues.map((i) => i.code), contains('action-not-allowed'));
  });

  test('restricted legacy action slot obeys allow list', () async {
    final library = OpenUiLibrary(
      root: const _Restricted(),
      components: const [_Restricted()],
    );
    const source =
        'root = Restricted({type: "open_url", url: "https://example.com"})';
    final session = OpenUiSession(library)..update(source, streaming: false);
    addTearDown(session.dispose);
    final events = <ActionEvent>[];
    await session.run(
      session.root!.props.action('action'),
      label: '',
      emit: events.add,
    );
    expect(events.single.type, ActionEvent.openUrl);
    expect(events.single.params, {'url': 'https://example.com'});
    final report = library.validate(
      source,
      policy: const ValidationPolicy(allowedActions: {}),
    );
    expect(report.ok, isFalse);
    expect(report.issues.map((i) => i.code), contains('action-not-allowed'));
  });
}
