/// Renders Open Intelligent UI answers (OpenUI Lang 1.0 programs) as Flutter
/// widgets: a port of thesysdev/open-intelligent-ui.
library;

export 'package:open_intelligent_ui_core/lucide.dart';
export 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart'
    hide OpenUiView;
export 'package:open_intelligent_ui_maps/open_intelligent_ui_maps.dart';
export 'package:open_intelligent_ui_math/open_intelligent_ui_math.dart';
export 'package:open_intelligent_ui_web/open_intelligent_ui_web.dart';

export 'src/batteries.dart' show OpenUiView, intelligentUiBuilders;
export 'src/wikimedia.dart' show WikimediaImageSearch;
