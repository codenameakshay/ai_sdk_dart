/// A read-only record the host gives a session, such as a server tool result. A program reads it as
/// `$name`; writes to it are ignored and it is never part of `OpenUiSession.state`.
final class BoundRecord {
  BoundRecord(this.name, this.value, {this.description = '', this.schema}) {
    if (!_identifier.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'Must be an identifier, without the \$',
      );
    }
  }

  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Without the `$`.
  final String name;

  /// JSON.
  final Object? value;

  final String description;

  /// JSON Schema for the prompt; null infers the type from [value].
  final Map<String, Object?>? schema;

  /// The program's spelling of this record, `$name`.
  String get variable => '\$$name';
}
