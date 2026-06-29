import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Image generation via [generateImage] with gpt-image-1.
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
  String? _emptyMessage;

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
      _emptyMessage = null;
      _imageBytes = null;
    });

    try {
      final result = await generateImage(
        model: OpenAIProvider(apiKey: openAiApiKey).image('gpt-image-1'),
        prompt: prompt,
      );
      setState(() {
        if (result.images.isEmpty) {
          // Avoid touching result.image (images.first), which throws on an
          // empty list. Show a calm empty state instead of crashing.
          _emptyMessage =
              'The model returned an empty response — no image was '
              'generated. (Image generation may be unavailable for this '
              'API key.)';
        } else {
          _imageBytes = result.images.first.bytes;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Image generation failed: $e';
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
      appBar: AppBar(title: const Text('Image Generation')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Generate images with gpt-image-1 (OpenAI).',
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
                child: Image.memory(_imageBytes!, fit: BoxFit.contain),
              ),
            ],
            if (_emptyMessage != null) ...[
              const SizedBox(height: 16),
              Card(
                color: scheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.image_not_supported_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _emptyMessage!,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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
