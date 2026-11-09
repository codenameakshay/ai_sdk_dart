import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

void main() {
  for (final source in [
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([Button("Go", {type: "open_url", url: $url})])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each([1], "it", Button("Go", {type: "open_url", url: $url}))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([Button("Go", Action([{type: "open_url", url: $url}]))])',
    r'root = Col([@Each([{type: "open_url", url: "https://example.com"}], "it", Button("Go", it))])',
    r'root = Col([@Each([{action: {type: "open_url", url: "https://example.com"}}], "it", Button("Go", it.action))])',
    r'root = Col([@Each([{selected: {type: "open_url", url: "https://example.com"}}], "it", Button("Go", it.selected))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each([{type: "open_url", url: $url}], "it", Button("Go", it))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each([{action: {type: "open_url", url: $url}}], "it", Button("Go", it.action))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each({items: [{type: "open_url", url: $url}]}.items, "it", Button("Go", it))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each({items: [{type: "open_url", url: $url}]}["items"], "it", Button("Go", it))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each([{selected: {type: "open_url", url: $url}}], "it", Button("Go", it.selected))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each([{selected: {type: "open_url", url: $url}}], "it", Button("Go", it["selected"]))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each([{items: [{type: "open_url", url: $url}]}], "group", @Each(group.items, "it", Button("Go", it)))])',
    r'$url = "https://example.com"'
        '\n'
        r'root = Col([@Each([{url: $url}], "it", Button("Go", Action([{type: "open_url", url: it.url}])))])',
    r'$kind = "open_url"'
        '\n'
        r'root = Col([@Each([1], "it", Button("Go", {type: $kind, url: "https://example.com"}))])',
    r'$extra = 1'
        '\n'
        r'root = Col([@Each([{url: "https://example.com", extra: $extra}], "it", Button("Go", Action([{type: "open_url", url: it.url}])))])',
    r'$extra = 1'
        '\n'
        r'root = Col([@Each([{kind: "open_url", url: "https://example.com", extra: $extra}], "it", Button("Go", {type: it.kind, url: "https://example.com"}))])',
    r'$steps = [{type: "open_url", url: "https://example.com"}]'
        '\n'
        r'root = Col([Button("Go", {steps: $steps})])',
    r'$steps = [{type: "open_url", url: "https://example.com"}]'
        '\n'
        r'root = Col([Button("Go", Action($steps))])',
    r'$step = {type: "open_url", url: "https://example.com"}'
        '\n'
        r'root = Col([Button("Go", {steps: [$step]})])',
  ]) {
    test('statically known legacy action obeys allow list: $source', () async {
      final session = OpenUiSession(intelligentUi)
        ..update(source, streaming: false);
      addTearDown(session.dispose);
      final events = <ActionEvent>[];
      await session.run(
        session.root!.props.elements('children').single.props.action('action'),
        label: 'Go',
        emit: events.add,
      );
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

  test('nested array step data stays passive', () async {
    const source =
        r'$x = 1'
        '\n'
        r'root = Col([@Each([1], "it", Button("Go", {steps: [[$x]]}))])';
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

  test('cyclic plan-step member validation terminates', () {
    const source =
        r'$record = {steps: [$record.steps]}'
        '\n'
        r'root = Col([Button("Go", $record)])';
    final report = intelligentUi.validate(
      source,
      policy: const ValidationPolicy(allowedActions: {}),
    );
    expect(report.hasRoot, isTrue);
  });
}
