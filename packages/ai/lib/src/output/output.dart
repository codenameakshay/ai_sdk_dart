import '../tools/tool.dart';

/// Structured output specification for generate/stream operations.
sealed class Output<T> {
  const Output();

  static Output<String> text() => const TextOutput();

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

  static Output<String> choice({
    required List<String> options,
    String? name,
    String? description,
  }) {
    return ChoiceOutput(options: options, name: name, description: description);
  }

  static Output<Object?> json({String? name, String? description}) {
    return JsonOutput(name: name, description: description);
  }
}

class TextOutput extends Output<String> {
  const TextOutput();
}

class ObjectOutput<T> extends Output<T> {
  const ObjectOutput({required this.schema, this.name, this.description});

  final Schema<T> schema;
  final String? name;
  final String? description;
}

class ArrayOutput<T> extends Output<List<T>> {
  const ArrayOutput({required this.element, this.name, this.description});

  final Schema<T> element;
  final String? name;
  final String? description;
}

class ChoiceOutput extends Output<String> {
  const ChoiceOutput({required this.options, this.name, this.description});

  final List<String> options;
  final String? name;
  final String? description;
}

class JsonOutput extends Output<Object?> {
  const JsonOutput({this.name, this.description});

  final String? name;
  final String? description;
}
