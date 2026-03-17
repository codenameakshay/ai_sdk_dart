import '../tools/tool.dart';

/// Structured output specification for [generateText] and [streamText].
///
/// Mirrors the Output API from the JS AI SDK v6. Use [text], [object],
/// [array], [choice], or [json] to specify the expected structure.
sealed class Output<T> {
  const Output();

  /// Plain text output (default when no output is specified).
  static Output<String> text() => const TextOutput();

  /// Schema-validated object output.
  ///
  /// [schema] defines the JSON structure; [name] and [description] provide
  /// optional LLM guidance.
  static Output<T> object<T>({
    required Schema<T> schema,
    String? name,
    String? description,
  }) {
    return ObjectOutput<T>(
      schema: schema,
      name: name,
      description: description,
    );
  }

  /// Array of typed elements; each element conforms to [element] schema.
  static Output<List<T>> array<T>({
    required Schema<T> element,
    String? name,
    String? description,
  }) {
    return ArrayOutput<T>(
      element: element,
      name: name,
      description: description,
    );
  }

  /// Fixed string options (e.g. for classification).
  ///
  /// Output will be exactly one of [options].
  static Output<String> choice({
    required List<String> options,
    String? name,
    String? description,
  }) {
    return ChoiceOutput(options: options, name: name, description: description);
  }

  /// Unstructured JSON output; no schema validation.
  static Output<Object?> json({String? name, String? description}) {
    return JsonOutput(name: name, description: description);
  }
}

/// Plain text output variant.
class TextOutput extends Output<String> {
  const TextOutput();
}

/// Object output with schema validation.
class ObjectOutput<T> extends Output<T> {
  const ObjectOutput({required this.schema, this.name, this.description});

  final Schema<T> schema;
  final String? name;
  final String? description;
}

/// Array output with typed element schema.
class ArrayOutput<T> extends Output<List<T>> {
  const ArrayOutput({required this.element, this.name, this.description});

  final Schema<T> element;
  final String? name;
  final String? description;
}

/// Choice output with fixed string options.
class ChoiceOutput extends Output<String> {
  const ChoiceOutput({required this.options, this.name, this.description});

  final List<String> options;
  final String? name;
  final String? description;
}

/// Unstructured JSON output.
class JsonOutput extends Output<Object?> {
  const JsonOutput({this.name, this.description});

  final String? name;
  final String? description;
}
