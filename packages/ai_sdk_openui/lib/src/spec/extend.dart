import 'library.dart';
import 'schema.dart';

/// A component for [LibraryExtension.addComponents]; with [slots] it also joins those unions.
final class ComponentAddition {
  const ComponentAddition(this.component, {this.slots});

  /// The component to add.
  final ComponentSpec component;

  /// "Parent.prop" or "Parent" (when it has one content slot) to place the component in.
  final List<String>? slots;
}

/// lang-core `LibraryExtension`.
final class LibraryExtension {
  const LibraryExtension({
    this.addComponents = const [],
    this.overrideComponents = const [],
    this.removeComponents = const [],
    this.addFunctions = const [],
    this.addActions = const [],
  });

  /// Components to add, each optionally placed in content slots.
  final List<ComponentAddition> addComponents;

  /// Components that replace an existing one with the same typeName.
  final List<ComponentSpec> overrideComponents;

  /// Components to drop from the library, every union and every group.
  final List<String> removeComponents;

  /// Functions to append.
  final List<FunctionSpec> addFunctions;

  /// Actions to append.
  final List<ActionSpec> addActions;
}

extension OpenUiLibraryExtend on OpenUiLibrary {
  /// lang-core `library.extend()`: a derived library; this one is untouched.
  OpenUiLibrary extend(LibraryExtension extension) =>
      _extendLibrary(this, extension);
}

Never _fail(String message) => throw ArgumentError('[extend] $message');

OpenUiLibrary _extendLibrary(OpenUiLibrary base, LibraryExtension ext) {
  final byName = <String, ComponentSpec>{...base.components};
  final known = <String>{...base.components.keys};
  final touched = <String>{};
  final slotRequests = <String, List<String>>{};

  void put(ComponentSpec c) {
    byName[c.typeName] = c;
    known.add(c.typeName);
    touched.add(c.typeName);
  }

  for (final add in ext.addComponents) {
    final name = add.component.typeName;
    if (byName.containsKey(name)) {
      _fail('Component "$name" already exists. Use override.');
    }
    final slots = add.slots;
    if (slots != null && slots.isEmpty) {
      _fail('"slots" for "$name" is empty. Omit it to only list it.');
    }
    put(add.component);
    if (slots != null) slotRequests[name] = slots;
  }

  final overridden = <String>{};
  for (final comp in ext.overrideComponents) {
    final name = comp.typeName;
    if (!byName.containsKey(name)) {
      _fail('Cannot override "$name": not in the library. Use add.');
    }
    if (!overridden.add(name)) _fail('Component "$name" is overridden twice.');
    put(comp);
  }

  final removed = <String>{...ext.removeComponents};
  for (final name in removed) {
    if (touched.contains(name)) {
      _fail(
        'Cannot remove "$name": it is added or overridden in the same call.',
      );
    }
    if (byName.remove(name) == null) {
      _fail('Cannot remove "$name": not in the library.');
    }
    if (name == base.rootName) {
      _fail('Cannot remove "$name": it is the library root.');
    }
  }

  final slots = [
    for (final c in byName.values)
      for (final e in c.props.entries)
        if (slotUnion(e.value, known) != null) '${c.typeName}.${e.key}',
  ];

  final placements = <String, List<String>>{};
  for (final request in slotRequests.entries) {
    for (final slot in request.value) {
      final path = _resolveSlot(slot, request.key, slots, byName);
      final placed = placements.putIfAbsent(path, () => []);
      if (!placed.contains(request.key)) placed.add(request.key);
    }
  }

  final rebuilt = <String, ComponentSpec>{};
  for (final c in byName.values) {
    final props = c.props;
    var changed = false;
    final next = <String, Schema>{};
    for (final e in props.entries) {
      final s = e.value;
      final path = '${c.typeName}.${e.key}';
      final out = rebindComponents(
        s,
        known: known,
        removed: removed,
        slot: slotUnion(s, known),
        added: placements[path] ?? const [],
        path: path,
      );
      if (!identical(out, s)) changed = true;
      next[e.key] = out;
    }
    rebuilt[c.typeName] = changed
        ? _Rebuilt(c.typeName, c.description, next)
        : c;
  }

  final groups = <ComponentGroup>[];
  for (final g in base.groups) {
    final comps = [
      for (final c in g.components)
        if (!removed.contains(c.typeName)) rebuilt[c.typeName] ?? c,
    ];
    if (comps.isEmpty) continue;
    final notes = [
      for (final n in g.notes)
        if (!removed.any((r) => RegExp('\\b$r\\b').hasMatch(n))) n,
    ];
    groups.add(ComponentGroup(g.name, comps, notes: notes));
  }

  return OpenUiLibrary(
    root: rebuilt[base.rootName]!,
    components: rebuilt.values.toList(),
    groups: groups,
    functions: [...base.functions, ...ext.addFunctions],
    actions: [...base.actions, ...ext.addActions],
  );
}

String _resolveSlot(
  String slot,
  String name,
  List<String> slots,
  Map<String, ComponentSpec> byName,
) {
  if (slots.contains(slot)) return slot;
  final parent = slot.split('.').first;
  final candidates = [
    for (final s in slots)
      if (s.startsWith('$parent.')) s,
  ];
  if (!slot.contains('.') && candidates.length == 1) return candidates.single;
  final what = 'Slot "$slot" for "$name"';
  if (!byName.containsKey(parent)) {
    _fail('$what: "$parent" is not in the library.');
  }
  if (candidates.isEmpty) {
    _fail(
      '$what: "$parent" has no content slot (a prop that is a union of components, or an optional or array of one).',
    );
  }
  _fail(
    '$what must be one content slot. Candidates: ${candidates.join(', ')}.',
  );
}

/// A component whose props an extension rewrote; keeps its name and description.
final class _Rebuilt implements ComponentSpec {
  _Rebuilt(this.typeName, this.description, this.props);

  @override
  final String typeName;
  @override
  final String description;
  @override
  final Map<String, Schema> props;
}
