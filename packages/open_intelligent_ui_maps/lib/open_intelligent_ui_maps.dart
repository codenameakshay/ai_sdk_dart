/// Map and MapMarker components for Open Intelligent UI, drawn with flutter_map.
library;

import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

import 'src/map.dart';

export 'src/map.dart' show buildMap, buildMapMarker;
export 'src/osrm.dart' show OsrmStreetRoute;

/// The builders this package adds to an Open Intelligent UI renderer.
const Map<String, OpenUiBuilder> mapBuilders = {
  'Map': buildMap,
  'MapMarker': buildMapMarker,
};
