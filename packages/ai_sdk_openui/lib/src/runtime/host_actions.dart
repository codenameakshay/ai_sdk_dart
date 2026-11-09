import 'dart:convert';

import '../lang/js.dart';

/// What a handled action's host call returned.
sealed class ActionResult {
  const ActionResult();
}

final class ActionSuccess extends ActionResult {
  const ActionSuccess([this.data]);

  /// JSON the host returns with the success, such as the id of the record
  /// it wrote. It is saved with the session state, and later steps of the
  /// same plan read it from [ActionInvocation.results] and
  /// `ActionEvent.results`.
  final Object? data;
}

final class ActionFailure extends ActionResult {
  const ActionFailure(this.message);
  final String message;
}

/// One run of a handled action. Send [idempotencyKey] with the write: a
/// retry of the same write sends the same key.
final class ActionInvocation {
  const ActionInvocation({
    required this.name,
    required this.params,
    required this.idempotencyKey,
    required this.attempt,
    this.formState = const {},
    this.formName,
    this.results = const {},
  });

  final String name;

  /// JSON, as [ActionEvent.params].
  final Map<String, Object?> params;

  /// `<16 hex digits>-<attempt>`.
  final String idempotencyKey;
  final int attempt;
  final Map<String, Object?> formState;
  final String? formName;

  /// The [ActionSuccess.data] of the handled actions that succeeded earlier
  /// in the same plan, by action name.
  final Map<String, Object?> results;
}

typedef ActionHandler =
    Future<ActionResult> Function(ActionInvocation invocation);

/// [unknown]: a run was cut off by a restore and the host's
/// `OpenUiSession.resolveAction` has not said yet whether it went through.
enum ActionPhase { idle, pending, done, failed, unknown }

final class ActionStatus {
  const ActionStatus({
    required this.phase,
    required this.idempotencyKey,
    this.message,
    this.confirm,
    this.disabled = false,
  });

  final ActionPhase phase;

  /// The key the next run sends.
  final String idempotencyKey;

  /// The failure message.
  final String? message;

  /// Ask this before running.
  final String? confirm;

  /// Pending, unknown, or done with `disableAfterSuccess`.
  final bool disabled;
}

/// The session state key that saves statuses.
const actionStateKey = '__openui_actions';

int _fnv1a(List<int> bytes, int seed) {
  var h = seed;
  for (final b in bytes) {
    // x * 16777619 mod 2^32 (16777619 = 2^24 + 0x193), with no product above 2^53.
    final x = h ^ b;
    h = (x * 0x193 + ((x & 0xff) << 24)) % 0x100000000;
  }
  return h;
}

Object? _sorted(Object? v) => switch (v) {
  Map() => {
    for (final k in [...v.keys.map((k) => '$k')]..sort()) k: _sorted(v[k]),
  },
  List() => [for (final x in v) _sorted(x)],
  _ => v,
};

/// The 16-hex base key of a handled action run: FNV-1a (two 32-bit seeds)
/// over the JSON of the scope, name and key-sorted params. It never depends
/// on where the control sits, so a list that grows keeps each item's key.
String actionBaseKey(String scope, String name, Map<String, Object?> params) {
  final bytes = utf8.encode(Js.stringify([scope, name, _sorted(params)]));
  String hex(int seed) => _fnv1a(bytes, seed).toRadixString(16).padLeft(8, '0');
  return '${hex(0x811c9dc5)}${hex(0x01000193)}';
}
