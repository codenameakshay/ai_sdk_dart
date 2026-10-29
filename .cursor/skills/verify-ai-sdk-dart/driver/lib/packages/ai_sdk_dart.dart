// Verification checks for package:ai_sdk_dart, split by owner:
// ai_sdk_dart_text.dart (features/ai_sdk_dart-text.md) and
// ai_sdk_dart_platform.dart (features/ai_sdk_dart-platform.md).
import '../harness.dart';
import 'ai_sdk_dart_platform.dart';
import 'ai_sdk_dart_text.dart';

final checks = PackageChecks('ai_sdk_dart', [...textChecks, ...platformChecks]);
