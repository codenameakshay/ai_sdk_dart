import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';

void main() {
  final weatherSchema = validatedJsonSchema<Map<String, dynamic>>(
    schema: {
      'type': 'object',
      'required': ['city'],
      'properties': {
        'city': {'type': 'string'},
      },
      'additionalProperties': false,
    },
    fromJson: (json) => json,
  );
  final weather = weatherSchema.fromJson({'city': 'Paris'});
  if (weather['city'] != 'Paris') throw StateError('Invalid decoded city');
}
