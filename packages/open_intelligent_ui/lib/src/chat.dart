import 'package:open_intelligent_ui_chat/open_intelligent_ui_chat.dart' as chat;
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart'
    show OpenUiBuilderLookup;

import 'batteries.dart';

/// [chat.OpenUiChat] with every Open Intelligent UI builder and this package's
/// default services.
final class OpenUiChat extends chat.OpenUiChat {
  OpenUiChat({
    required super.controller,
    super.agent,
    super.send,
    super.library,
    OpenUiBuilderLookup? builders,
    super.tools,
    super.onAction,
    super.fallbackServices = batteryServices,
    super.locale,
    super.records,
  }) : super(builders: builders ?? intelligentUiBuilders);
}
