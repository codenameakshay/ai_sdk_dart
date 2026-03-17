import 'dart:typed_data';

import 'package:ai/ai.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Image generation via [generateImage] with DALL-E 3.
class ImageGenPage extends StatefulWidget {
  const ImageGenPage({super.key});

  @override
  State<ImageGenPage> createState() => _ImageGenPageState();
}

class _ImageGenPageState extends State<ImageGenPage> {
  final _promptController = TextEditingController();
  bool _loading = false;
  Uint8List? _imageBytes;
  String? _error;

  Future<void> _generate() async {
    if (openAiApiKey.isEmpty) {
      setState(() {
        _error = 'Set OPENAI_API_KEY to use image generation.';
      });
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _imageBytes = null;
    });

    try {
      final result = await generateImage(
        model: OpenAIProvider(apiKey: openAiApiKey).image('dall-e-3'),
        prompt: prompt,
      );
      setState(() {
        _imageBytes = result.image.bytes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Generation'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Generate images with DALL-E 3 (OpenAI).',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _promptController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Prompt',
                hintText: 'A futuristic city at sunset…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _generate,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image),
              label: Text(_loading ? 'Generating…' : 'Generate'),
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 24),
              Text('Result', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  fit: BoxFit.contain,
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
