import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';
import 'package:test/test.dart';

void main() {
  test('compiled validator retains its enum after source mutation', () {
    final allowed = ['original'];
    final source = <String, dynamic>{
      'type': 'object',
      'properties': {
        'value': {'enum': allowed},
      },
    };
    final validator = JsonSchemaValidator(source);

    allowed
      ..clear()
      ..add('changed');

    expect(validator.validate({'value': 'original'}), isEmpty);
    expect(validator.validate({'value': 'changed'}), isNotEmpty);
  });
}
