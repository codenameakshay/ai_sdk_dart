import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import '../config.dart';

enum _Provider { openai, anthropic, google }

/// Demonstrates the OpenAI Responses API (`OpenAIProvider.responses`) with a
/// hosted [OpenAIWebSearchTool] toggle — its citations surface as ordinary
/// [LanguageModelV4SourcePart]s, rendered with [SourceCitations]. A provider
/// selector lets Anthropic/Google join in via the shared top-level
/// `reasoning:` option, rendered with [ReasoningView] when the model streams
/// any.
///
/// [testModel], when supplied, replaces every provider's model so tests can
/// exercise streaming, sources, and reasoning against a fake model with no
/// network access.
class ResponsesPage extends StatefulWidget {
  const ResponsesPage({super.key, this.testModel});

  final LanguageModelV4? testModel;

  @override
  State<ResponsesPage> createState() => _ResponsesPageState();
}

class _ResponsesPageState extends State<ResponsesPage> {
  final _promptController = TextEditingController(
    text: 'What is notable about the number 41?',
  );
  _Provider _provider = _Provider.openai;
  bool _webSearch = true;
  bool _streaming = false;
  String? _error;
  String _text = '';
  String _reasoningText = '';
  final List<LanguageModelV4SourcePart> _sources = [];
  CancellationToken? _cancellation;

  LanguageModelV4 _modelFor(_Provider provider) {
    if (widget.testModel != null) return widget.testModel!;
    return switch (provider) {
      _Provider.openai => OpenAIProvider(
        apiKey: openAiApiKey,
      ).responses('gpt-4.1-mini'),
      _Provider.anthropic => AnthropicProvider(apiKey: anthropicApiKey)(
        'claude-sonnet-4-20250514',
      ),
      _Provider.google => GoogleGenerativeAIProvider(apiKey: googleApiKey)(
        'gemini-2.0-flash',
      ),
    };
  }

  String _apiKeyFor(_Provider provider) => switch (provider) {
    _Provider.openai => openAiApiKey,
    _Provider.anthropic => anthropicApiKey,
    _Provider.google => googleApiKey,
  };

  Future<void> _ask() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _streaming) return;
    if (widget.testModel == null && _apiKeyFor(_provider).isEmpty) {
      setState(() => _error = 'Set the API key for the selected provider.');
      return;
    }

    setState(() {
      _streaming = true;
      _error = null;
      _text = '';
      _reasoningText = '';
      _sources.clear();
    });

    final cancellation = CancellationToken();
    _cancellation = cancellation;
    try {
      final result = await streamText(
        model: _modelFor(_provider),
        prompt: prompt,
        reasoning: LanguageModelV4Reasoning.medium,
        abortSignal: cancellation,
        // A hosted tool: the provider runs the search itself and returns
        // citations as source parts — no local tool executor involved.
        providerDefinedTools: _webSearch && _provider == _Provider.openai
            ? [OpenAIWebSearchTool()]
            : const [],
      );
      result.text.then((_) {}, onError: (_) {});
      await for (final event in result.stream) {
        if (!mounted) return;
        switch (event) {
          case StreamTextTextDeltaEvent(:final delta):
            setState(() => _text += delta);
          case StreamTextReasoningDeltaEvent(:final delta):
            setState(() => _reasoningText += delta);
          case StreamTextSourceEvent(:final source):
            setState(() => _sources.add(source));
          case StreamTextErrorEvent(:final error):
            throw error;
          default:
            break;
        }
      }
      if (mounted) setState(() => _streaming = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _streaming = false;
      });
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  void _stop() {
    _cancellation?.cancel();
    _cancellation = null;
    if (mounted) setState(() => _streaming = false);
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Responses')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'OpenAI Responses API with a hosted web-search tool, plus a '
              'provider selector for Anthropic/Google reasoning.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<_Provider>(
              segments: const [
                ButtonSegment(
                  value: _Provider.openai,
                  label: Text('OpenAI (Responses)'),
                ),
                ButtonSegment(
                  value: _Provider.anthropic,
                  label: Text('Anthropic'),
                ),
                ButtonSegment(value: _Provider.google, label: Text('Google')),
              ],
              selected: {_provider},
              onSelectionChanged: _streaming
                  ? null
                  : (s) => setState(() => _provider = s.first),
            ),
            SwitchListTile(
              key: const ValueKey('responses-web-search-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Web search (OpenAI hosted tool)'),
              subtitle: const Text('Renders citations as SourceCitations.'),
              value: _webSearch,
              onChanged: _provider == _Provider.openai
                  ? (v) => setState(() => _webSearch = v)
                  : null,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('responses-prompt-field'),
              controller: _promptController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
              onSubmitted: (_) => _ask(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  key: const ValueKey('responses-ask-button'),
                  onPressed: _streaming ? null : _ask,
                  icon: _streaming
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_streaming ? 'Asking…' : 'Ask'),
                ),
                if (_streaming) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  ),
                ],
              ],
            ),
            if (_reasoningText.isNotEmpty) ...[
              const SizedBox(height: 20),
              ReasoningView(text: _reasoningText, initiallyExpanded: true),
            ],
            if (_text.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: StreamingTextView(
                  text: _text,
                  isStreaming: _streaming,
                  style: textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ],
            if (_sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              SourceCitations(sources: _sources),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
