import 'dart:io';
import 'dart:typed_data';

import 'package:ai/ai.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../config.dart';

/// Speech-to-text via [transcribe] (OpenAI Whisper).
class SttPage extends StatefulWidget {
  const SttPage({super.key});

  @override
  State<SttPage> createState() => _SttPageState();
}

class _SttPageState extends State<SttPage> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _loading = false;
  String? _transcription;
  String? _error;

  Future<void> _toggleRecord() async {
    if (openAiApiKey.isEmpty) {
      setState(() => _error = 'Set OPENAI_API_KEY to use STT.');
      return;
    }

    if (_recording) {
      final path = await _recorder.stop();
      if (path == null) return;
      setState(() {
        _recording = false;
        _loading = true;
        _error = null;
      });

      try {
        final bytes = await _readFile(path);
        final result = await transcribe(
          model: OpenAIProvider(apiKey: openAiApiKey)
              .transcription('whisper-1'),
          audio: bytes,
        );
        setState(() {
          _transcription = result.text;
          _loading = false;
        });
      } catch (e) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } else {
      if (await _recorder.hasPermission()) {
        final tempDir = Directory.systemTemp;
        final path = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
        setState(() {
          _recording = true;
          _error = null;
          _transcription = null;
        });
      } else {
        setState(() => _error = 'Microphone permission denied.');
      }
    }
  }

  Future<Uint8List> _readFile(String path) async {
    return File(path).readAsBytes();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech-to-Text'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Record audio and transcribe with OpenAI Whisper.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: FilledButton.icon(
                onPressed: _loading ? null : _toggleRecord,
                icon: _recording
                    ? const Icon(Icons.stop)
                    : _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mic),
                label: Text(
                  _recording
                      ? 'Stop & Transcribe'
                      : _loading
                          ? 'Transcribing…'
                          : 'Start Recording',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            if (_transcription != null) ...[
              const SizedBox(height: 24),
              Text('Transcription', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _transcription!,
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
