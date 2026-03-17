import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Embeddings and [cosineSimilarity] — compare two texts.
/// Supports OpenAI and Google embedding models.
class EmbeddingsPage extends StatefulWidget {
  const EmbeddingsPage({super.key});

  @override
  State<EmbeddingsPage> createState() => _EmbeddingsPageState();
}

class _EmbeddingsPageState extends State<EmbeddingsPage> {
  final _text1Controller = TextEditingController(text: 'A cat sits on a mat.');
  final _text2Controller = TextEditingController(
    text: 'A kitten rests on a rug.',
  );
  bool _loading = false;
  double? _similarity;
  String? _error;
  String _provider = 'openai';

  Future<void> _compare() async {
    final text1 = _text1Controller.text.trim();
    final text2 = _text2Controller.text.trim();
    if (text1.isEmpty || text2.isEmpty) return;

    final useOpenAi = _provider == 'openai';
    if (useOpenAi && openAiApiKey.isEmpty) {
      setState(() => _error = 'Set OPENAI_API_KEY for OpenAI embeddings.');
      return;
    }
    if (!useOpenAi && googleApiKey.isEmpty) {
      setState(() => _error = 'Set GOOGLE_API_KEY for Google embeddings.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _similarity = null;
    });

    try {
      if (useOpenAi) {
        final e1 = await embed(
          model: OpenAIProvider(
            apiKey: openAiApiKey,
          ).embedding('text-embedding-3-small'),
          value: text1,
        );
        final e2 = await embed(
          model: OpenAIProvider(
            apiKey: openAiApiKey,
          ).embedding('text-embedding-3-small'),
          value: text2,
        );
        setState(() {
          _similarity = cosineSimilarity(e1.embedding, e2.embedding);
          _loading = false;
        });
      } else {
        final e1 = await embed(
          model: GoogleGenerativeAIProvider(
            apiKey: googleApiKey,
          ).embedding('text-embedding-004'),
          value: text1,
        );
        final e2 = await embed(
          model: GoogleGenerativeAIProvider(
            apiKey: googleApiKey,
          ).embedding('text-embedding-004'),
          value: text2,
        );
        setState(() {
          _similarity = cosineSimilarity(e1.embedding, e2.embedding);
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _text1Controller.dispose();
    _text2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Embeddings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Compare two texts using embeddings. Similarity is 0–1 (1 = identical).',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'openai', label: Text('OpenAI')),
                ButtonSegment(value: 'google', label: Text('Google')),
              ],
              selected: {_provider},
              onSelectionChanged: (s) => setState(() => _provider = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text1Controller,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Text 1',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text2Controller,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Text 2',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _compare,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.compare),
              label: Text(_loading ? 'Comparing…' : 'Compare'),
            ),
            if (_similarity != null) ...[
              const SizedBox(height: 24),
              Text('Similarity', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _similarity!.toStringAsFixed(4),
                  style: textTheme.headlineMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
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
