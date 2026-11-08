import 'package:ai_sdk_openui/src/lang/parser.dart';
import 'package:ai_sdk_openui/src/runtime/store.dart';
import 'package:test/test.dart';

void main() {
  group('set', () {
    test(
      'an equal value, or an object with the same entries, does not notify',
      () {
        final store = Store();
        var notified = 0;
        store.listen(() => notified++);

        store.set('form', {'a': 1, 'b': 'x'});
        expect(notified, 1);
        store.set('form', {'b': 'x', 'a': 1});
        expect(notified, 1);
        store.set('n', 3);
        store.set('n', 3);
        expect(notified, 2);
      },
    );

    test(
      'an object with a different value, key or size notifies and replaces',
      () {
        final store = Store();
        var notified = 0;
        store.listen(() => notified++);
        store.set('form', {'a': 1});

        store.set('form', {'a': 2});
        expect(store.get('form'), {'a': 2});
        store.set('form', {'b': 2});
        expect(store.get('form'), {'b': 2});
        store.set('form', {'b': 2, 'c': 3});
        expect(store.get('form'), {'b': 2, 'c': 3});
        expect(notified, 4);
      },
    );

    test('has tells a stored null from a missing key', () {
      final store = Store()..set('a', null);
      expect(store.has('a'), isTrue);
      expect(store.has('b'), isFalse);
      expect(store.get('a'), isNull);
    });

    test('a cancelled listener is not called again', () {
      final store = Store();
      var notified = 0;
      final cancel = store.listen(() => notified++);
      store.set('a', 1);
      cancel();
      store.set('a', 2);
      expect(notified, 1);
    });
  });

  group('initialize', () {
    test('a key still at its declared default follows a new default', () {
      final store = Store()..initialize({'a': 1}, {});
      store.initialize({'a': 2}, {});
      expect(store.snapshot, {'a': 2});
    });

    test('a key the user changed keeps its value', () {
      final store = Store()..initialize({'a': 1}, {});
      store.set('a', 5);
      store.initialize({'a': 3}, {});
      expect(store.snapshot, {'a': 5});
    });

    test('a key set back as pristine follows defaults again', () {
      final store = Store()..initialize({'a': 1}, {});
      store.set('a', 5);
      store.set('a', 1, pristine: true);
      store.initialize({'a': 4}, {});
      expect(store.snapshot, {'a': 4});
    });

    test('a persisted value wins over the default and stays', () {
      final store = Store()..initialize({'a': 1}, {'a': 9});
      expect(store.snapshot, {'a': 9});
      store.initialize({'a': 2}, {});
      expect(store.snapshot, {'a': 9});
    });

    test('a list default equal by value is not a change', () {
      final store = Store();
      var notified = 0;
      store
        ..initialize({
          'xs': [1, 2],
        }, {})
        ..listen(() => notified++);
      store.initialize({
        'xs': [1, 2],
      }, {});
      expect(notified, 0);
      store.initialize({
        'xs': [1, 2, 3],
      }, {});
      expect(notified, 1);
      expect(store.get('xs'), [1, 2, 3]);
    });

    test('a new default key is added and notifies once', () {
      final store = Store();
      var notified = 0;
      store.listen(() => notified++);
      store.initialize({'a': 1, 'b': 2}, {});
      expect(store.snapshot, {'a': 1, 'b': 2});
      expect(notified, 1);
    });
  });

  test('the snapshot cannot be edited and dispose clears everything', () {
    final store = Store()..set('a', 1);
    expect(() => store.snapshot['b'] = 2, throwsUnsupportedError);
    var notified = 0;
    store.listen(() => notified++);
    store.dispose();
    store.set('a', 2);
    expect(store.snapshot, {'a': 2});
    expect(notified, 0);
  });

  // Ported from lang-core 1.0.0 runtime/__tests__/store.test.ts.
  group('store defaults while streaming', () {
    const program =
        'root = Col([shopping, copyButton, dinnerCards], 4)\n'
        r'$ingredients = ["500 g (about 1 lb) ground beef", "12 small tortillas or taco shells", "1 packet taco seasoning (about 28 g / 1 oz)", "1 small head lettuce", "2 medium tomatoes", "1 small onion", "150 g (about 1½ cups) shredded cheddar", "2 avocados", "200 g (about ¾ cup) salsa", "150 g (about ⅔ cup) sour cream", "2 limes"]'
        '\n'
        r'$checked = []'
        '\n'
        r'$dishes = [{name: "Lemon chicken pasta", time: "30 minutes"}, {name: "Chickpea and spinach curry", time: "35 minutes"}]'
        '\n'
        r'shopping = Card([Col(@Each($ingredients, "item", Pressable([Text(item)], @Set($checked, @Toggle($checked, item)), @Includes($checked, item))))])'
        '\n'
        r'copyButton = Button("Copy whole shopping list", @CopyToClipboard(@Join($ingredients, "\n")))'
        '\n'
        r'dinnerCards = Grid(@Each($dishes, "dish", Card([Title(dish.name), Button("Get recipe", @ToAssistant("Recipe for " + dish.name, {dishName: dish.name}))])))'
        '\n';
    final schema = CompiledSchema.fromJsonSchema(const {});

    void streamInto(Store store, [void Function(String text)? onStep]) {
      final sp = StreamParser(schema, rootName: 'Col');
      for (var end = 20; end < program.length + 20; end += 20) {
        final text = program.substring(0, end.clamp(0, program.length));
        store.initialize(sp.set(text).stateDeclarations, const {});
        onStep?.call(text);
      }
    }

    test(
      'ends with the batch-parse state: full values, no half-typed names',
      () {
        final store = Store();
        streamInto(store);
        final batch = parseProgram(
          program,
          schema,
          rootName: 'Col',
        ).stateDeclarations;
        expect(store.snapshot, batch);
        expect(store.get(r'$ingredients'), hasLength(11));
        expect(store.snapshot.keys.toList()..sort(), [
          r'$checked',
          r'$dishes',
          r'$ingredients',
        ]);
      },
    );

    test('keeps a value the user set mid-stream', () {
      final store = Store();
      streamInto(store, (text) {
        final checked = store.get(r'$checked');
        if (text.contains('\$checked = []\n') &&
            !(checked is List && checked.isNotEmpty)) {
          store.set(r'$checked', ['2 limes']);
        }
      });
      expect(store.get(r'$checked'), ['2 limes']);
      expect(store.get(r'$ingredients'), hasLength(11));
    });

    for (final end in ['', '\n']) {
      test(
        'declares a \$name that ends the program (trailing ${end.isEmpty ? '""' : r'"\n"'})',
        () {
          final src = 'root = Col([Input(email)])\nemail = \$email$end';
          final sp = StreamParser(schema, rootName: 'Col');
          final store = Store();
          for (var i = 5; i < src.length; i += 5) {
            store.initialize(
              sp.set(src.substring(0, i)).stateDeclarations,
              const {},
            );
          }
          store.initialize(
            sp.set(src, complete: true).stateDeclarations,
            const {},
          );
          final batch = parseProgram(
            src,
            schema,
            rootName: 'Col',
          ).stateDeclarations;
          expect(batch, {r'$email': null});
          expect(store.snapshot, batch);
        },
      );
    }

    test(
      'a value restored with pristine: true (@Reset) can still be replaced',
      () {
        final store = Store()
          ..initialize({r'$title': 'Quarterly rev'}, const {});
        store
          ..set(r'$title', 'user edit')
          ..set(r'$title', 'Quarterly rev', pristine: true)
          ..initialize({r'$title': 'Quarterly revenue'}, const {});
        expect(store.get(r'$title'), 'Quarterly revenue');
      },
    );
  });
}
