import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Demonstrates [streamObject] directly (rather than the ergonomic
/// `ObjectStreamController`) so the page can show both v3 incremental
/// surfaces side by side:
///
/// - `partialObjectStream` — immutable, *unvalidated* JSON snapshots, safe to
///   render live but never to treat as a complete instance of `T`.
/// - `patchStream` — the JSON Patch (RFC 6902-style) diff between each
///   snapshot and the previous one.
///
/// The final `object` future is decoded through [validatedJsonSchema], which
/// runs schema validation before the decoder — an invalid final document
/// throws rather than silently repairing into a "successful" object.
class ObjectStreamPage extends StatefulWidget {
  const ObjectStreamPage({super.key, this.testModel});

  final LanguageModelV4? testModel;

  @override
  State<ObjectStreamPage> createState() => _ObjectStreamPageState();
}

class _ObjectStreamPageState extends State<ObjectStreamPage> {
  late final _openAi = OpenAIProvider(apiKey: openAiApiKey);
  final _countryController = TextEditingController(text: 'Japan');

  static final _schema = validatedJsonSchema<Map<String, dynamic>>(
    schema: const {
      'type': 'object',
      'properties': {
        'country': {'type': 'string'},
        'capital': {'type': 'string'},
        'population': {'type': 'string'},
        'currency': {'type': 'string'},
        'languages': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'funFact': {'type': 'string'},
      },
      'required': [
        'country',
        'capital',
        'population',
        'currency',
        'languages',
        'funFact',
      ],
      'additionalProperties': false,
    },
    fromJson: (json) => json,
  );

  CancellationToken? _cancellation;
  Map<String, dynamic>? _partial;
  Map<String, dynamic>? _validated;
  final List<StreamObjectPatchOperation> _recentPatch = [];
  bool _streaming = false;
  String? _error;

  @override
  void dispose() {
    _cancellation?.cancel();
    _openAi.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final country = _countryController.text.trim();
    if (country.isEmpty || _streaming) return;

    setState(() {
      _streaming = true;
      _error = null;
      _partial = null;
      _validated = null;
      _recentPatch.clear();
    });

    final cancellation = CancellationToken();
    _cancellation = cancellation;
    try {
      final result = await streamObject(
        model: widget.testModel ?? _openAi('gpt-4.1-mini'),
        schema: _schema,
        instructions: 'Generate a JSON country profile.',
        prompt: 'Generate a country profile for $country.',
        abortSignal: cancellation,
      );
      final partialSub = result.partialObjectStream.listen((snapshot) {
        if (!mounted || cancellation.isCancelled) return;
        setState(() => _partial = snapshot);
      }, onError: (Object _) {});
      final patchSub = result.patchStream.listen((patch) {
        if (!mounted || cancellation.isCancelled) return;
        setState(() {
          _recentPatch
            ..clear()
            ..addAll(patch);
        });
      }, onError: (Object _) {});
      try {
        // validatedJsonSchema runs schema validation before the decoder, so
        // an incomplete/invalid final document throws here rather than
        // silently becoming a "successful" object.
        final validated = await result.object;
        if (!mounted || cancellation.isCancelled) return;
        setState(() {
          _validated = validated;
          _streaming = false;
        });
      } finally {
        await partialSub.cancel();
        await patchSub.cancel();
      }
    } catch (e) {
      if (!mounted || cancellation.isCancelled) return;
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

  void _reset() {
    _cancellation?.cancel();
    _cancellation = null;
    setState(() {
      _partial = null;
      _validated = null;
      _recentPatch.clear();
      _error = null;
      _streaming = false;
      _countryController.text = 'Japan';
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Object Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
            onPressed: _reset,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Streams a JSON object as the model generates it: an immutable '
              'unvalidated partial snapshot, its JSON Patch diff, and a final '
              'value validated by validatedJsonSchema before it is decoded.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _countryController,
                    decoration: InputDecoration(
                      labelText: 'Country',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _generate(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _streaming ? null : _generate,
                  icon: _streaming
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('Generate'),
                ),
              ],
            ),
            if (_streaming)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'),
                ),
              ),
            if (_partial != null && _validated == null) ...[
              const SizedBox(height: 24),
              Text(
                'Partial snapshot (unvalidated)',
                style: textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _ProfileCard(data: _partial!),
            ],
            if (_recentPatch.isNotEmpty && _validated == null) ...[
              const SizedBox(height: 16),
              Text('Latest JSON Patch', style: textTheme.titleSmall),
              const SizedBox(height: 8),
              _PatchLog(operations: _recentPatch),
            ],
            if (_validated != null) ...[
              const SizedBox(height: 24),
              Text('Country Profile (validated)', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              _ProfileCard(data: _validated!),
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

class _PatchLog extends StatelessWidget {
  const _PatchLog({required this.operations});

  final List<StreamObjectPatchOperation> operations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final op in operations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${op.op} ${op.path}${op.value == null ? '' : ' = ${op.value}'}',
                style: textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final rows = [
      if (data['country'] != null)
        ('Country', '${data['country']}', Icons.flag_outlined),
      if (data['capital'] != null)
        ('Capital', '${data['capital']}', Icons.location_city_outlined),
      if (data['population'] != null)
        ('Population', '${data['population']}', Icons.people_outline),
      if (data['currency'] != null)
        ('Currency', '${data['currency']}', Icons.payments_outlined),
    ];

    final languages = data['languages'];
    final funFact = data['funFact'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(row.$3, size: 20, color: scheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      '${row.$1}:',
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(row.$2, style: textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
            if (languages is List && languages.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.translate_outlined,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Languages:',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: languages
                          .map(
                            (l) => Chip(
                              label: Text('$l'),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ],
            if (funFact != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$funFact',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
