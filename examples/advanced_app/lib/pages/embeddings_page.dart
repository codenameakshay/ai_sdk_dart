import 'package:ai_sdk_dart/ai_sdk_dart.dart';
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
  late final _openAi = OpenAIProvider(apiKey: openAiApiKey);
  late final _google = GoogleGenerativeAIProvider(apiKey: googleApiKey);
  final _text1Controller = TextEditingController(text: 'A cat sits on a mat.');
  final _text2Controller = TextEditingController(
    text: 'A kitten rests on a rug.',
  );
  bool _loading = false;
  double? _similarity;
  String? _error;
  String _provider = 'openai';

  final _batchController = TextEditingController(
    text: 'cat\nkitten\ndog\npuppy\ncar\ntruck',
  );
  int _maxEmbeddingsPerCall = 2;
  int _maxParallelCalls = 2;
  bool _batchLoading = false;
  String? _batchError;
  EmbedManyResult<String>? _batchResult;

  Future<void> _runBatch() async {
    final values = _batchController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (values.isEmpty || _batchLoading) return;

    final useOpenAi = _provider == 'openai';
    if (useOpenAi && openAiApiKey.isEmpty) {
      setState(() => _batchError = 'Set OPENAI_API_KEY for OpenAI embeddings.');
      return;
    }
    if (!useOpenAi && googleApiKey.isEmpty) {
      setState(() => _batchError = 'Set GOOGLE_API_KEY for Google embeddings.');
      return;
    }

    setState(() {
      _batchLoading = true;
      _batchError = null;
      _batchResult = null;
    });

    try {
      // maxEmbeddingsPerCall bounds how many values go in each provider
      // request; maxParallelCalls bounds how many of those requests are
      // in flight at once. The SDK preserves input order regardless of which
      // batch finishes first.
      final result = await embedMany<String>(
        model: useOpenAi
            ? _openAi.embedding('text-embedding-3-small')
            : _google.embedding('text-embedding-004'),
        values: values,
        maxEmbeddingsPerCall: _maxEmbeddingsPerCall,
        maxParallelCalls: _maxParallelCalls,
      );
      if (!mounted) return;
      setState(() {
        _batchResult = result;
        _batchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _batchError = '$e';
        _batchLoading = false;
      });
    }
  }

  Future<void> _compare() async {
    final text1 = _text1Controller.text.trim();
    final text2 = _text2Controller.text.trim();
    if (text1.isEmpty || text2.isEmpty || _loading) return;

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
          model: _openAi.embedding('text-embedding-3-small'),
          value: text1,
        );
        final e2 = await embed(
          model: _openAi.embedding('text-embedding-3-small'),
          value: text2,
        );
        if (!mounted) return;
        setState(() {
          _similarity = cosineSimilarity(e1.embedding, e2.embedding);
          _loading = false;
        });
      } else {
        final e1 = await embed(
          model: _google.embedding('text-embedding-004'),
          value: text1,
        );
        final e2 = await embed(
          model: _google.embedding('text-embedding-004'),
          value: text2,
        );
        if (!mounted) return;
        setState(() {
          _similarity = cosineSimilarity(e1.embedding, e2.embedding);
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _openAi.dispose();
    _google.dispose();
    _text1Controller.dispose();
    _text2Controller.dispose();
    _batchController.dispose();
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
              onSelectionChanged: _loading || _batchLoading
                  ? null
                  : (s) => setState(() => _provider = s.first),
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
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text('Batch embed (embedMany)', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'One value per line. maxEmbeddingsPerCall bounds each request; '
              'maxParallelCalls bounds how many requests run at once.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _batchController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Values',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StepperField(
                    label: 'maxEmbeddingsPerCall',
                    value: _maxEmbeddingsPerCall,
                    min: 1,
                    max: 8,
                    onChanged: (v) => setState(() => _maxEmbeddingsPerCall = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StepperField(
                    label: 'maxParallelCalls',
                    value: _maxParallelCalls,
                    min: 1,
                    max: 4,
                    onChanged: (v) => setState(() => _maxParallelCalls = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _batchLoading ? null : _runBatch,
              icon: _batchLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.dataset_outlined),
              label: Text(_batchLoading ? 'Embedding…' : 'Run batch embed'),
            ),
            if (_batchResult != null) ...[
              const SizedBox(height: 16),
              Text(
                '${_batchResult!.embeddings.length} embeddings'
                '${_batchResult!.usage?.tokens == null ? '' : ' · ${_batchResult!.usage!.tokens} tokens'}',
                style: textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              for (final entry in _batchResult!.embeddings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${entry.value} → ${entry.embedding.length} dims',
                    style: textTheme.bodySmall,
                  ),
                ),
            ],
            if (_batchError != null) ...[
              const SizedBox(height: 16),
              Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _batchError!,
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

class _StepperField extends StatelessWidget {
  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label: $value',
              style: textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
