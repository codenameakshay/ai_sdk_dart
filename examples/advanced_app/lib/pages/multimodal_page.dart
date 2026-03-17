import 'dart:typed_data';

import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';

/// Multimodal: send image + text, get model analysis.
/// Uses [LanguageModelV3ImagePart] in messages.
class MultimodalPage extends StatefulWidget {
  const MultimodalPage({super.key});

  @override
  State<MultimodalPage> createState() => _MultimodalPageState();
}

class _MultimodalPageState extends State<MultimodalPage> {
  final _questionController = TextEditingController();
  Uint8List? _imageBytes;
  String? _mediaType;
  bool _loading = false;
  String? _response;
  String? _error;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _mediaType = 'image/jpeg';
      _response = null;
      _error = null;
    });
  }

  Future<void> _captureImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _mediaType = 'image/jpeg';
      _response = null;
      _error = null;
    });
  }

  Future<void> _analyze() async {
    if (openAiApiKey.isEmpty) {
      setState(() => _error = 'Set OPENAI_API_KEY to use this feature.');
      return;
    }
    if (_imageBytes == null) {
      setState(() => _error = 'Pick an image first.');
      return;
    }

    final question = _questionController.text.trim();
    if (question.isEmpty) {
      setState(() => _error = 'Enter a question about the image.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _response = null;
    });

    try {
      final result = await generateText(
        model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
        messages: [
          ModelMessage.parts(
            role: ModelMessageRole.user,
            parts: [
              LanguageModelV3ImagePart(
                image: DataContentBytes(_imageBytes!),
                mediaType: _mediaType ?? 'image/jpeg',
              ),
              LanguageModelV3TextPart(text: question),
            ],
          ),
        ],
      );
      setState(() {
        _response = result.text;
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
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Multimodal')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Send an image and a question. The model analyzes the image.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _captureImage,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _questionController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Question',
                hintText: 'What do you see in this image?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading || _imageBytes == null ? null : _analyze,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.analytics),
              label: Text(_loading ? 'Analyzing…' : 'Analyze'),
            ),
            if (_response != null) ...[
              const SizedBox(height: 24),
              Text('Response', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _response!,
                  style: textTheme.bodyMedium?.copyWith(height: 1.6),
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
