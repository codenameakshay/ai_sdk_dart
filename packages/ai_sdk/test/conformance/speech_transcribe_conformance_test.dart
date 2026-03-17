import 'dart:typed_data';

import 'package:ai_sdk/ai_sdk.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('speech and transcription conformance', () {
    // ── generateSpeech() ──────────────────────────────────────────────────

    group('generateSpeech()', () {
      test('returns audio bytes and mediaType from model', () async {
        final audio = Uint8List.fromList([1, 2, 3, 4]);
        final model = FakeSpeechModel(audio: audio, mediaType: 'audio/mpeg');

        final result = await generateSpeech(model: model, text: 'Hello world');
        expect(result.audio, audio);
        expect(result.mediaType, 'audio/mpeg');
      });

      test('passes text to model doGenerate options', () async {
        final model = FakeSpeechModel(audio: Uint8List(0));

        await generateSpeech(model: model, text: 'test utterance');
        expect(model.lastOptions?.text, 'test utterance');
      });

      test('passes voice option to model', () async {
        final model = FakeSpeechModel(audio: Uint8List(0));

        await generateSpeech(model: model, text: 'Hello', voice: 'alloy');
        expect(model.lastOptions?.voice, 'alloy');
      });

      test('passes format option to model', () async {
        final model = FakeSpeechModel(audio: Uint8List(0));

        await generateSpeech(model: model, text: 'Hello', format: 'mp3');
        expect(model.lastOptions?.format, 'mp3');
      });

      test('passes speed option to model', () async {
        final model = FakeSpeechModel(audio: Uint8List(0));

        await generateSpeech(model: model, text: 'Hello', speed: 1.5);
        expect(model.lastOptions?.speed, 1.5);
      });

      test('passes providerOptions to model', () async {
        final model = FakeSpeechModel(audio: Uint8List(0));
        const providerOptions = <String, Map<String, dynamic>>{
          'openai': {'quality': 'hd'},
        };

        await generateSpeech(
          model: model,
          text: 'Hello',
          providerOptions: providerOptions,
        );
        expect(model.lastOptions?.providerOptions, providerOptions);
      });

      test('result audio is non-null even for empty audio', () async {
        final model = FakeSpeechModel(audio: Uint8List(0));
        final result = await generateSpeech(model: model, text: 'silent');
        expect(result.audio, isNotNull);
      });

      test('different models can return different mediaTypes', () async {
        final mp3Model = FakeSpeechModel(
          audio: Uint8List(1),
          mediaType: 'audio/mpeg',
        );
        final wavModel = FakeSpeechModel(
          audio: Uint8List(2),
          mediaType: 'audio/wav',
        );

        final mp3Result = await generateSpeech(model: mp3Model, text: 'hi');
        final wavResult = await generateSpeech(model: wavModel, text: 'hi');

        expect(mp3Result.mediaType, 'audio/mpeg');
        expect(wavResult.mediaType, 'audio/wav');
      });
    });

    // ── transcribe() ──────────────────────────────────────────────────────

    group('transcribe()', () {
      test('returns transcribed text from model', () async {
        final model = FakeTranscriptionModel('Hello, world!');
        final result = await transcribe(
          model: model,
          audio: Uint8List.fromList([0, 1, 2]),
        );
        expect(result.text, 'Hello, world!');
      });

      test('passes audio bytes to model doGenerate options', () async {
        final model = FakeTranscriptionModel('text');
        final audio = Uint8List.fromList([10, 20, 30]);

        await transcribe(model: model, audio: audio);
        expect(model.lastOptions?.audio, audio);
      });

      test('passes audioMediaType option to model', () async {
        final model = FakeTranscriptionModel('hello');

        await transcribe(
          model: model,
          audio: Uint8List(0),
          audioMediaType: 'audio/wav',
        );
        expect(model.lastOptions?.audioMediaType, 'audio/wav');
      });

      test('passes language option to model', () async {
        final model = FakeTranscriptionModel('bonjour');

        await transcribe(model: model, audio: Uint8List(0), language: 'fr');
        expect(model.lastOptions?.language, 'fr');
      });

      test('passes prompt option to model', () async {
        final model = FakeTranscriptionModel('text');

        await transcribe(
          model: model,
          audio: Uint8List(0),
          prompt: 'transcript of a meeting',
        );
        expect(model.lastOptions?.prompt, 'transcript of a meeting');
      });

      test('passes providerOptions to model', () async {
        final model = FakeTranscriptionModel('text');
        const opts = <String, Map<String, dynamic>>{
          'openai': {'timestamps': true},
        };

        await transcribe(
          model: model,
          audio: Uint8List(0),
          providerOptions: opts,
        );
        expect(model.lastOptions?.providerOptions, opts);
      });

      test('result text is non-empty for non-empty transcript', () async {
        final model = FakeTranscriptionModel('The quick brown fox');
        final result = await transcribe(
          model: model,
          audio: Uint8List.fromList([1, 2, 3]),
        );
        expect(result.text, isNotEmpty);
      });
    });
  });
}
