import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

class Weather {
  Weather(this.city, this.temperature);
  final String city;
  final num temperature;
}

class PartialModel extends MockLanguageModelV4 {
  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(
    stream: Stream.fromIterable(const [
      StreamPartTextDelta(id: 'text', delta: '{"city":"Paris",'),
      StreamPartTextDelta(id: 'text', delta: '"temperature":12}'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]),
  );
}

void main() {
  test(
    'partial snapshots remain JSON while only the final object is validated and decoded',
    () async {
      var decodeCount = 0;
      final schema = validatedJsonSchema<Weather>(
        schema: {
          'type': 'object',
          'required': ['city', 'temperature'],
          'properties': {
            'city': {'type': 'string'},
            'temperature': {'type': 'number'},
          },
        },
        fromJson: (json) {
          decodeCount++;
          return Weather(json['city'] as String, json['temperature'] as num);
        },
      );
      final result = await streamObject(model: PartialModel(), schema: schema);
      final finalObject = result.object;
      final snapshots = await result.partialObjectStream.toList();
      expect(snapshots, isNotEmpty);
      expect(snapshots.last, {'city': 'Paris', 'temperature': 12});
      expect((await finalObject).temperature, 12);
      expect(decodeCount, 1);
    },
  );
}
