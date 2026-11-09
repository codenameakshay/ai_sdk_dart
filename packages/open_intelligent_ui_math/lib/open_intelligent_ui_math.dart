/// Math component for Open Intelligent UI: LaTeX formulas drawn with flutter_math_fork.
library;

import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

import 'src/math.dart';

export 'src/math.dart' show buildMath;

/// The builders this package adds to an Open Intelligent UI renderer.
const Map<String, OpenUiBuilder> mathBuilders = {'Math': buildMath};
