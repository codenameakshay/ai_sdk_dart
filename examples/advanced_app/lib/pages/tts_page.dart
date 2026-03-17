import 'package:ai/ai.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Text-to-speech via [generateSpeech] (OpenAI TTS).
class TtsPage extends StatefulWidget {
  const TtsPage({super.key});

  @override
  State<TtsPage> createState() => _TtsPageState();
}

class _TtsPageState extends State<TtsPage> {
  final _textController = TextEditingController(
    text: 'Hello! This is a sample of text-to-speech from the AI SDK.',
  );
  bool _loading = false;
  String? _error;
  final _player = AudioPlayer();

  Future<void> _speak() async {
    if (openAiApiKey.isEmpty) {
      setState(() => _error = 'Set OPENAI_API_KEY to use TTS.');
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await generateSpeech(
        model: OpenAIProvider(apiKey: openAiApiKey).speech('tts-1'),
        text: text,
        voice: 'alloy',
      );

      await _player.stop();
      await _player.play(
        BytesSource(result.audio, mimeType: result.mediaType),
      );
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _stop() async {
    await _player.stop();
  }

  @override
  void dispose() {
    _textController.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Text-to-Speech'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Convert text to speech with OpenAI TTS.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Text',
                hintText: 'Enter text to speak…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : _speak,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.record_voice_over),
                  label: Text(_loading ? 'Generating…' : 'Speak'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
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
