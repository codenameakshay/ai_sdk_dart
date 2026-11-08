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
}
