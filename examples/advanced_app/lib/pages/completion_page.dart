import 'package:ai/ai.dart';
import 'package:ai_sdk_flutter/ai_sdk_flutter.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Demonstrates [CompletionController] — single-turn text completion.
class CompletionPage extends StatefulWidget {
  const CompletionPage({super.key});

  @override
  State<CompletionPage> createState() => _CompletionPageState();
}

class _CompletionPageState extends State<CompletionPage> {
  late final CompletionController _completion;
  final _promptController = TextEditingController();

  static const _presets = [
    'Explain async/await in Dart in 3 sentences.',
    'Write a haiku about Flutter.',
    'List 5 tips for writing clean Dart code.',
    'What is the difference between StatelessWidget and StatefulWidget?',
  ];

  @override
  void initState() {
    super.initState();
    _completion = CompletionController(
      agent: ToolLoopAgent(
        model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
        instructions: 'You are a helpful assistant. Be concise.',
      ),
      onError: (err) => _showSnackBar('Error: $err'),
    );
  }

  @override
  void dispose() {
    _completion.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _promptController.text.trim();
    if (text.isEmpty || _completion.isStreaming) return;
    _completion.complete(text);
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completion'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear',
            onPressed: () {
              _completion.clear();
              _promptController.clear();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _completion,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Quick prompts', style: textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presets
                      .map(
                        (p) => ActionChip(
                          label: Text(
                            p.length > 36 ? '${p.substring(0, 36)}…' : p,
                          ),
                          onPressed: _completion.isStreaming
                              ? null
                              : () {
                                  _promptController.text = p;
                                  _completion.complete(p);
                                },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _promptController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Prompt',
                    hintText: 'Ask anything…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _completion.isStreaming ? null : _submit,
                  icon: _completion.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _completion.isStreaming ? 'Generating…' : 'Generate',
                  ),
                ),
                if (_completion.isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _completion.stop,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                    ),
                  ),
                if (_completion.completion.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text('Response', style: textTheme.labelLarge),
                      const Spacer(),
                      if (_completion.isStreaming)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _completion.completion,
                      style: textTheme.bodyMedium?.copyWith(height: 1.6),
                    ),
                  ),
                ],
                if (_completion.error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${_completion.error}',
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
