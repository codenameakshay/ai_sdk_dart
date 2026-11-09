import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

void main() {
  final lean = intelligentUiWithout(optionalIuiComponents);

  test('intelligentUiWithout({}) is intelligentUi', () {
    expect(identical(intelligentUiWithout({}), intelligentUi), isTrue);
    expect(identical(chatPromptFor(intelligentUi), chatPrompt), isTrue);
  });

  test('a lean library leaves out the optional components', () {
    final names = lean.components.keys.toSet();
    for (final c in [
      IuiComponent.math,
      IuiComponent.map,
      IuiComponent.mapMarker,
      IuiComponent.youTube,
      IuiComponent.htmlView,
    ]) {
      expect(names, isNot(contains(c.typeName)));
    }
    expect(names, hasLength(50));
    expect(lean.parse('root = Col([Math("x")])').isClean, isFalse);
  });

  test('omitting Map omits MapMarker', () {
    final library = intelligentUiWithout({IuiComponent.map});
    expect(library.components.keys, isNot(contains('Map')));
    expect(library.components.keys, isNot(contains('MapMarker')));
  });

  test('the lean chat prompt names no missing component', () {
    const medium =
        'Pick the medium that shows the idea: Chart for numbers across time or categories; Svg drawings for shapes, parts and movement; Table for comparisons; Flashcard and Celebration for learning and games.';
    expect(chatPromptFor(lean).additionalRules, contains(medium));
    final prompt = lean.systemPrompt(chatPromptFor(lean));
    for (final missing in [
      'Map(',
      'MapMarker(',
      'HtmlView(',
      'YouTube(',
      'Math(',
    ]) {
      expect(prompt, isNot(contains(missing)));
    }
    final dashboard = lean.systemPrompt(dashboardPrompt(library: lean));
    expect(dashboard, contains(medium));
    expect(dashboard, isNot(contains('HtmlView(')));
  });
}
