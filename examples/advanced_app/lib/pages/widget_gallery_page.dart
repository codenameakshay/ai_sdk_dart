import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

/// A live catalogue of the prebuilt `ai_sdk_flutter_ui` widgets, driven by
/// static sample data and a synthetic stream — so every widget renders and
/// reacts **without an API key or a network call**.
///
/// Each section shows one widget the way you'd use it against a real
/// [ChatController] / generation result; the interactive ones (approve/deny,
/// copy, suggestions, scroll-to-bottom, object streaming) actually work.
class WidgetGalleryPage extends StatefulWidget {
  const WidgetGalleryPage({super.key});

  @override
  State<WidgetGalleryPage> createState() => _WidgetGalleryPageState();
}

class _WidgetGalleryPageState extends State<WidgetGalleryPage> {
  // Drives the live ObjectStreamView demo.
  final ObjectStreamController<Map<String, dynamic>> _object =
      ObjectStreamController<Map<String, dynamic>>();

  // Backs the ScrollToBottomButton demo's mini list.
  final ScrollController _miniScroll = ScrollController();

  // Sample assistant turn assembled from content parts — exactly the shape an
  // assistant `ModelMessage.parts` takes after a tool-using turn.
  static final _assistantTurn = ModelMessage.parts(
    role: ModelMessageRole.assistant,
    parts: const [
      LanguageModelV3ReasoningPart(
        text: 'The user asked about the weather in Tokyo, so I should call the '
            'getWeather tool and summarise the result.',
      ),
      LanguageModelV3TextPart(text: 'It is currently 22°C and sunny in Tokyo.'),
      LanguageModelV3ToolCallPart(
        toolCallId: 'call_1',
        toolName: 'getWeather',
        input: {'city': 'Tokyo'},
      ),
      LanguageModelV3SourcePart(
        id: 's1',
        url: 'https://weather.example.com/tokyo',
        title: 'Tokyo Weather — example.com',
      ),
    ],
  );

  static const _toolResults = [
    LanguageModelV3ToolResultPart(
      toolCallId: 'call_1',
      toolName: 'getWeather',
      output: ToolResultOutputText('{"tempC": 22, "condition": "sunny"}'),
    ),
  ];

  static const _approvalRequest = LanguageModelV3ToolApprovalRequestPart(
    approvalId: 'approval_call_2',
    toolCall: LanguageModelV3ToolCallPart(
      toolCallId: 'call_2',
      toolName: 'deleteFile',
      input: {'path': '/Users/me/reports/q3.pdf'},
    ),
  );

  static const _usage = LanguageModelV3Usage(
    inputTokens: 1240,
    outputTokens: 318,
    totalTokens: 1558,
  );

  @override
  void dispose() {
    _object.dispose();
    _miniScroll.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
  }

  /// Feeds the [ObjectStreamView] a fake partial-object stream so the live
  /// streaming UI can be seen offline.
  void _streamSampleObject() {
    _object.bind(_fakeProfileStream());
  }

  static Stream<Map<String, dynamic>> _fakeProfileStream() async* {
    const fields = {
      'country': 'Japan',
      'capital': 'Tokyo',
      'population': '125 million',
      'currency': 'Japanese yen (JPY)',
    };
    final accumulated = <String, dynamic>{};
    for (final entry in fields.entries) {
      accumulated[entry.key] = entry.value;
      yield Map<String, dynamic>.of(accumulated);
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Every widget below is a prebuilt component from ai_sdk_flutter_ui, '
          'rendered with sample data — no API key required.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),

        _Section(
          title: 'PromptSuggestions',
          subtitle: 'Tappable starters for an empty conversation.',
          child: PromptSuggestions(
            title: 'Try asking',
            suggestions: const [
              'Summarise my notes',
              'Plan a trip to Kyoto',
              'Explain async/await',
            ],
            onSelected: (text) => _snack('Selected: $text'),
          ),
        ),

        _Section(
          title: 'TypingIndicator',
          subtitle: 'Shown while waiting for the first token.',
          child: const Align(
            alignment: Alignment.centerLeft,
            child: TypingIndicator(label: 'Assistant is typing'),
          ),
        ),

        _Section(
          title: 'AssistantMessageView',
          subtitle:
              'A whole assistant turn: reasoning + text + tool call (with its '
              'result) + a source, from one ModelMessage.parts.',
          child: AssistantMessageView(
            message: _assistantTurn,
            toolResults: _toolResults,
            onSourceTap: (source) => _snack('Open: ${source.url}'),
          ),
        ),

        _Section(
          title: 'ToolApprovalCard',
          subtitle: 'Human-in-the-loop gate for a sensitive tool call.',
          child: ToolApprovalCard(
            request: _approvalRequest,
            showReasonField: true,
            onApprove: (reason) =>
                _snack('Approved${reason == null ? '' : ' — $reason'}'),
            onDeny: (reason) =>
                _snack('Denied${reason == null ? '' : ' — $reason'}'),
          ),
        ),

        _Section(
          title: 'ToolCallCard',
          subtitle: 'A tool call and an errored tool call.',
          child: Column(
            children: const [
              ToolCallCard(
                call: LanguageModelV3ToolCallPart(
                  toolCallId: 'call_3',
                  toolName: 'calculate',
                  input: {'expression': '42 * 1.5'},
                ),
                result: LanguageModelV3ToolResultPart(
                  toolCallId: 'call_3',
                  toolName: 'calculate',
                  output: ToolResultOutputText('63'),
                ),
              ),
              ToolCallCard(
                call: LanguageModelV3ToolCallPart(
                  toolCallId: 'call_4',
                  toolName: 'fetchUrl',
                  input: {'url': 'https://nope.invalid'},
                ),
                result: LanguageModelV3ToolResultPart(
                  toolCallId: 'call_4',
                  toolName: 'fetchUrl',
                  isError: true,
                  output: ToolResultOutputText('SocketException: failed host '
                      'lookup'),
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'MessageActionsBar',
          subtitle: 'Per-message affordances — copy uses the real clipboard.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: MessageActionsBar(
              copyText: 'It is currently 22°C and sunny in Tokyo.',
              onCopied: () => _snack('Copied to clipboard'),
              onRegenerate: () => _snack('Regenerate'),
              onThumbUp: () => _snack('👍 Thanks for the feedback'),
              onThumbDown: () => _snack('👎 Thanks for the feedback'),
            ),
          ),
        ),

        _Section(
          title: 'Media — MessageImage & MessageAttachment',
          subtitle:
              'Multimodal parts rendered with core Flutter (falls back to a '
              'placeholder offline).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 280,
                height: 150,
                child: MessageImage(
                  image: LanguageModelV3ImagePart(
                    image: DataContentUrl(
                      Uri.parse('https://picsum.photos/seed/aisdk/280/150'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              MessageAttachment(
                file: LanguageModelV3FilePart(
                  data: DataContentUrl(
                    Uri.parse('https://example.com/design-spec.pdf'),
                  ),
                  mediaType: 'application/pdf',
                  filename: 'design-spec.pdf',
                ),
                onTap: () => _snack('Open attachment'),
              ),
            ],
          ),
        ),

        _Section(
          title: 'UsageView',
          subtitle: 'Token usage for a turn (ChatController.lastUsage).',
          child: const Align(
            alignment: Alignment.centerLeft,
            child: UsageView(usage: _usage),
          ),
        ),

        _Section(
          title: 'ChatErrorView',
          subtitle: 'Error banner with retry / dismiss.',
          child: ChatErrorView(
            error: 'Connection timed out after 30s',
            onRetry: () => _snack('Retry'),
            onDismiss: () => _snack('Dismissed'),
          ),
        ),

        _Section(
          title: 'ObjectStreamView',
          subtitle:
              'Renders an ObjectStreamController. Press Stream to feed it a '
              'synthetic partial-object stream.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: _streamSampleObject,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Stream a sample object'),
              ),
              const SizedBox(height: 12),
              ObjectStreamView<Map<String, dynamic>>(
                controller: _object,
                emptyState: Text(
                  'Press Stream to watch fields arrive live.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'ScrollToBottomButton',
          subtitle:
              'Appears when the list is scrolled up; tap it to jump to the '
              'latest. Scroll the mini list below.',
          child: SizedBox(
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: _miniScroll,
                      padding: const EdgeInsets.all(8),
                      itemCount: 30,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text('Message ${i + 1}'),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: ScrollToBottomButton(controller: _miniScroll),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled card wrapper used for each gallery entry.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
