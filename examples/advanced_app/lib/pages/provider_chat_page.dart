import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Multi-provider chat using [createProviderRegistry], rendered entirely with
/// the prebuilt [AiChatScaffold] widget.
///
/// Switch between OpenAI, Anthropic, and Google models from the app bar; each
/// switch rebuilds the [ToolLoopAgent] against the newly selected model.
class ProviderChatPage extends StatefulWidget {
  const ProviderChatPage({super.key});

  @override
  State<ProviderChatPage> createState() => _ProviderChatPageState();
}

class _ProviderChatPageState extends State<ProviderChatPage> {
  late final ProviderRegistry _registry;
  late final ChatController _chat;
  late ToolLoopAgent _agent;

  static const _modelIds = [
    'openai:gpt-4.1-mini',
    'anthropic:claude-sonnet-4-20250514',
    'google:gemini-2.0-flash',
  ];

  String _selectedModelId = _modelIds.first;

  @override
  void initState() {
    super.initState();
    _registry = createProviderRegistry({
      'openai': RegistrableProvider(
        languageModelFactory: (id) => OpenAIProvider(apiKey: openAiApiKey)(id),
        embeddingModelFactory: (id) =>
            OpenAIProvider(apiKey: openAiApiKey).embedding(id),
      ),
      'anthropic': RegistrableProvider(
        languageModelFactory: (id) =>
            AnthropicProvider(apiKey: anthropicApiKey)(id),
        embeddingModelFactory: (_) =>
            throw UnsupportedError('Anthropic has no embedding model'),
      ),
      'google': RegistrableProvider(
        languageModelFactory: (id) =>
            GoogleGenerativeAIProvider(apiKey: googleApiKey)(id),
        embeddingModelFactory: (id) =>
            GoogleGenerativeAIProvider(apiKey: googleApiKey).embedding(id),
      ),
    });
    _agent = _buildAgent(_selectedModelId);
    _chat = ChatController(onError: (err) => _showSnackBar('Error: $err'));
  }

  ToolLoopAgent _buildAgent(String modelId) => ToolLoopAgent(
    model: _registry.languageModel(modelId),
    instructions: 'You are a helpful assistant. Be concise.',
    maxSteps: 5,
  );

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Chat'),
        actions: [
          ListenableBuilder(
            listenable: _chat,
            builder: (context, child) => DropdownButton<String>(
              value: _selectedModelId,
              underline: const SizedBox(),
              items: _modelIds
                  .map(
                    (id) => DropdownMenuItem(
                      value: id,
                      child: Text(id.split(':').first),
                    ),
                  )
                  .toList(),
              onChanged: _chat.isLoading
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedModelId = v;
                        _agent = _buildAgent(v);
                      });
                    },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: _chat.clear,
          ),
        ],
      ),
      body: AiChatScaffold(controller: _chat, agent: _agent),
    );
  }
}
