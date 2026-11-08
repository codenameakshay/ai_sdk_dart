import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:open_intelligent_ui/chat.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

/// The trip page from the chat prompt's second example.
const lisbonProgram =
    r'''root = Col([title, intro, photos, facts, Title("Day by day", "md"), days, prefs])
$pace = "Relaxed"
title = Title("Three days in Lisbon", "xl")
intro = Text("Hills, tiled facades and the Tagus: start in **Alfama**, give a day to Belém, then take the train to Sintra.")
photos = Carousel([SearchImage("Alfama Lisbon", 1.25), SearchImage("Belém Tower", 1.25), SearchImage("Pena Palace", 1.25)], 260)
facts = Row([Badge("Best in April to June"), Badge("Tram 28", "info"), Badge("About €120 a day", "success")], 2, null, null, true)
days = Col(@Each(plan, "d", Row([Box([SearchImage(d.place, 1, "lg")], null, null, null, null, null, null, 96), Col([Text([Icon("map-pin", "sm"), " Day " + d.day + " · " + d.title], "md", null, "semibold"), Text(d.text, "sm", "muted")], 1)], 4, "start")), 5)
prefs = Card([Title("Make it yours", "sm"), Form([RadioGroup($pace, ["Relaxed", "Packed"], "Pace", "pills"), Button("Plan my trip", @ToAssistant("Tailor my Lisbon trip"))])], "soft")
plan = [{day: 1, title: "Alfama", place: "São Jorge Castle", text: "Climb to the castle, then lunch on grilled sardines."}, {day: 2, title: "Belém", place: "Jerónimos Monastery", text: "The monastery, the tower and pastéis de Belém."}, {day: 3, title: "Sintra", place: "Pena Palace", text: "Train from Rossio; book the palace for 9 AM."}]''';

/// The follow-up page for a trip tailored to [pace].
String tailoredProgram(String pace) {
  final packed = pace == 'Packed';
  return '''root = Col([title, intro, days, prep])
\$ready = false
title = Title("Lisbon at a ${pace.toLowerCase()} pace", "xl")
intro = Text("${packed ? 'Two sights a day and an early start.' : 'One sight a day and long lunches.'}")
days = Col(@Each(plan, "d", Card([Title("Day " + d.day + " · " + d.title, "sm"), Text(d.text, "sm", "muted")], "soft")), 3)
prep = Card([Title("Before you go", "sm"), Checkbox(\$ready, "Pena Palace tickets booked"), \$ready ? Badge("Ready for Sintra", "success") : Text("Book a day ahead in summer.", "sm", "muted")])
plan = ${packed ? _packedPlan : _relaxedPlan}''';
}

const _packedPlan =
    '[{day: 1, title: "Alfama and Baixa", text: "Castle at opening, then the Santa Justa lift and Rua Augusta."}, '
    '{day: 2, title: "Belém and LX Factory", text: "Monastery, tower and MAAT, then dinner at LX Factory."}, '
    '{day: 3, title: "Sintra and Cascais", text: "Pena Palace at 9 AM, Quinta da Regaleira, sunset in Cascais."}]';
const _relaxedPlan =
    '[{day: 1, title: "Alfama", text: "Wander to the castle, long lunch, fado at night."}, '
    '{day: 2, title: "Belém", text: "The monastery, then pastéis de Belém by the river."}, '
    '{day: 3, title: "Sintra", text: "Pena Palace only, with a picnic in the park."}]';

/// What the scripted model answers to [userText]: the tailored page for a
/// `@ToAssistant` turn that carries `$pace`, otherwise the trip page.
String scriptedReply(String userText) {
  final message = OpenUiMessage.parse(userText);
  if (message.context case [_, final Map<String, Object?> state, ...]) {
    return tailoredProgram(jsString(state[r'$pace'] ?? 'Relaxed'));
  }
  return lisbonProgram;
}

/// An offline model that streams [scriptedReply] in small chunks, so the
/// chat shows a page building up without an API key.
final class ScriptedModel extends LanguageModelV4 {
  ScriptedModel({
    this.chunk = 24,
    this.every = const Duration(milliseconds: 30),
  });

  final int chunk;
  final Duration every;

  @override
  String get provider => 'scripted';
  @override
  String get modelId => 'intelligent-ui-demo';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4GenerateResult(
    content: [LanguageModelV4TextPart(text: scriptedReply(_lastUser(options)))],
    finishReason: LanguageModelV4FinishReason.stop,
  );

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final text = scriptedReply(_lastUser(options));
    final out = StreamController<LanguageModelV4StreamPart>();
    out.add(const StreamPartTextStart(id: 't'));
    var at = 0;
    void tick(Timer timer) {
      if (at < text.length) {
        final end = (at + chunk).clamp(0, text.length);
        out.add(StreamPartTextDelta(id: 't', delta: text.substring(at, end)));
        at = end;
        return;
      }
      timer.cancel();
      out
        ..add(const StreamPartTextEnd(id: 't'))
        ..add(
          const StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.stop,
            rawFinishReason: 'stop',
          ),
        );
      unawaited(out.close());
    }

    final timer = Timer.periodic(every, tick);
    out.onCancel = timer.cancel;
    return LanguageModelV4StreamResult(stream: out.stream);
  }

  static String _lastUser(LanguageModelV4CallOptions options) {
    final user = options.prompt.messages.lastWhere(
      (m) => m.role == LanguageModelV4Role.user,
    );
    return user.content.whereType<LanguageModelV4TextPart>().map((p) {
      return p.text;
    }).join();
  }
}

/// A chat whose answers are Open Intelligent UI pages, from [model] or the
/// offline [ScriptedModel].
class ChatDemoPage extends StatefulWidget {
  const ChatDemoPage({super.key, this.model});

  final LanguageModelV4? model;

  @override
  State<ChatDemoPage> createState() => _ChatDemoPageState();
}

class _ChatDemoPageState extends State<ChatDemoPage> {
  final _controller = ChatController();
  late final _agent = ToolLoopAgent(
    model: widget.model ?? ScriptedModel(),
    instructions: intelligentUi.systemPrompt(chatPrompt),
  );
  late final _chat = OpenUiChat(
    controller: _controller,
    agent: _agent,
    tools: demoTools(),
  );

  @override
  void dispose() {
    _chat.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chat demo')),
    body: SafeArea(
      top: false,
      child: AiChatScaffold(
        controller: _controller,
        agent: _agent,
        chatMessageBuilder: _chat.buildMessage,
        hintText: 'Ask for a trip, a recipe, a chart…',
        emptyState: Center(
          child: PromptSuggestions(
            title: 'An offline model answers with Intelligent UI pages',
            suggestions: const ['Plan three days in Lisbon'],
            onSelected: (text) =>
                unawaited(_controller.sendMessage(agent: _agent, text: text)),
          ),
        ),
      ),
    ),
  );
}
