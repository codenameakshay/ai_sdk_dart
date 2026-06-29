/// Provider interface specification for the AI SDK Dart port.
///
/// This package defines the abstract interfaces that all provider packages
/// must implement. It mirrors the `@ai-sdk/provider` npm package.
library ai_sdk_provider;

// Core model interfaces
export 'src/language_model/language_model_v3.dart';
export 'src/language_model/language_model_v3_call_options.dart';
export 'src/language_model/language_model_v3_content.dart';
export 'src/language_model/language_model_v3_data_content.dart';
export 'src/language_model/language_model_v3_finish_reason.dart';
export 'src/language_model/language_model_v3_generate_result.dart';
export 'src/language_model/language_model_v3_prompt.dart';
export 'src/language_model/language_model_v3_stream_part.dart';
export 'src/language_model/language_model_v3_stream_result.dart';
export 'src/language_model/language_model_v3_tool.dart';
export 'src/language_model/language_model_v3_tool_choice.dart';
export 'src/language_model/language_model_v3_usage.dart';

// Embedding model interfaces
export 'src/embedding_model/embedding_model_v2.dart';
export 'src/embedding_model/embedding_model_v2_call_options.dart';
export 'src/embedding_model/embedding_model_v2_generate_result.dart';

// Image model interfaces
export 'src/image_model/image_model_v3.dart';
export 'src/image_model/image_model_v3_call_options.dart';
export 'src/image_model/image_model_v3_generate_result.dart';

// Speech model interfaces
export 'src/speech_model/speech_model_v1.dart';
export 'src/speech_model/speech_model_v1_call_options.dart';

// Transcription model interfaces
export 'src/transcription_model/transcription_model_v1.dart';
export 'src/transcription_model/transcription_model_v1_call_options.dart';

// Rerank model interfaces
export 'src/rerank_model/rerank_model_v1.dart';
export 'src/rerank_model/rerank_model_v1_call_options.dart';

// Shared types
export 'src/shared/json_value.dart';
export 'src/shared/provider_metadata.dart';
