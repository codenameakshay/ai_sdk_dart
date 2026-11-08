import '../lang/message.dart';
import 'session.dart';

/// react-ui `buildActionUserMessage`: the stored user turn for an
/// [ActionEvent.continueConversation] event. The message is the content; the
/// context is `["User clicked: <message>", formState, context?]`. Without a
/// message the content line is left out.
String buildActionUserMessage(ActionEvent event) {
  final built = buildMessage(
    content: event.humanFriendlyMessage,
    context: [
      'User clicked: ${event.humanFriendlyMessage}',
      event.formState,
      if (event.params.containsKey('context')) event.params['context'],
    ],
  );
  return event.humanFriendlyMessage.isNotEmpty
      ? built
      : built.substring(built.indexOf('\n') + 1);
}
