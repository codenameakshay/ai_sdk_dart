import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:test/test.dart';

void main() {
  final call = <String, dynamic>{
    'id': 'call-part',
    'type': 'tool_call',
    'callId': 'call-1',
    'name': 'search',
    'arguments': <String, dynamic>{},
  };
  final result = <String, dynamic>{
    'id': 'result-part',
    'type': 'tool_result',
    'callId': 'call-1',
    'output': null,
    'isError': false,
  };

  for (final flag in ['providerExecuted', 'preliminary', 'isDynamic']) {
    for (final malformed in ['true', 1, <String, dynamic>{}]) {
      test('rejects nonboolean $flag value $malformed on restore', () {
        final parts = [
          {...call, if (flag == 'providerExecuted') flag: malformed},
          {...result, if (flag != 'providerExecuted') flag: malformed},
        ];
        expect(
          () => ConversationCodec.decode({
            'schemaVersion': 1,
            'id': 'conversation-1',
            'messages': [
              {
                'id': 'message-1',
                'role': 'assistant',
                'status': 'complete',
                'parts': parts,
              },
            ],
          }),
          throwsA(isA<ConversationValidationException>()),
        );
      });
    }
  }
}
