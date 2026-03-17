import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Demonstrates [ObjectStreamController] — streams partial structured JSON.
///
/// The model generates a country profile as a typed map.
/// Each partial update is shown live as fields arrive.
class ObjectStreamPage extends StatefulWidget {
  const ObjectStreamPage({super.key});

  @override
  State<ObjectStreamPage> createState() => _ObjectStreamPageState();
}

class _ObjectStreamPageState extends State<ObjectStreamPage> {
  late final ObjectStreamController<Map<String, dynamic>> _objectController;
  final _countryController = TextEditingController(text: 'Japan');

  // JSON schema for a country profile
  static final _schema = Schema<Map<String, dynamic>>(
    jsonSchema: const {
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
    },
    fromJson: (json) => json,
  );

  @override
  void initState() {
    super.initState();
    _objectController = ObjectStreamController<Map<String, dynamic>>(
      onError: (err) => _showSnackBar('Error: $err'),
    );
  }

  @override
  void dispose() {
    _objectController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final country = _countryController.text.trim();
    if (country.isEmpty || _objectController.isStreaming) return;

    final streamResult = await streamText<Map<String, dynamic>>(
      model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
      prompt: 'Generate a country profile for $country.',
      output: Output.object(schema: _schema),
    );

    await _objectController.bind(
      streamResult.partialOutputStream.map((v) => v as Map<String, dynamic>),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            onPressed: () {
              _objectController.reset();
              _countryController.text = 'Japan';
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _objectController,
        builder: (context, _) {
          final obj = _objectController.value;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Streams a typed JSON object as the model generates it — '
                  'each field appears as soon as it arrives.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // Input
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
                      onPressed: _objectController.isStreaming
                          ? null
                          : _generate,
                      icon: _objectController.isLoading
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

                if (_objectController.isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _objectController.stop,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                    ),
                  ),

                // Live output card
                if (obj != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text('Country Profile', style: textTheme.titleMedium),
                      const Spacer(),
                      if (_objectController.isStreaming)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ProfileCard(data: obj),
                ],

                if (_objectController.error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${_objectController.error}',
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

/// Renders a country profile map with animated field appearance.
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
