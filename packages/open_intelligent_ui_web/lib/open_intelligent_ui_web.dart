/// HtmlView and YouTube components for Open Intelligent UI, drawn in a web view.
library;

import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

import 'src/html_view.dart';

export 'src/html_view.dart' show buildHtmlView, buildYouTube;

/// The builders this package adds to an Open Intelligent UI renderer.
const Map<String, OpenUiBuilder> webBuilders = {
  'HtmlView': buildHtmlView,
  'YouTube': buildYouTube,
};
