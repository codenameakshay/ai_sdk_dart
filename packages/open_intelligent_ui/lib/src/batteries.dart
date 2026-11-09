import 'package:flutter/widgets.dart';
import 'package:open_intelligent_ui_core/lucide.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart' as core;
import 'package:open_intelligent_ui_maps/open_intelligent_ui_maps.dart';
import 'package:open_intelligent_ui_math/open_intelligent_ui_math.dart';
import 'package:open_intelligent_ui_web/open_intelligent_ui_web.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> _launch(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication).then((_) {});

const core.OpenUiServices batteryServices = core.OpenUiServices(
  openUrl: _launch,
  icons: lucideIconResolver,
  fontFamily: 'packages/open_intelligent_ui/Inter',
);

final core.OpenUiBuilderLookup _all = core.composeBuilders([
  mapBuilders,
  webBuilders,
  mathBuilders,
]);

/// Every Open Intelligent UI builder.
core.OpenUiBuilder? intelligentUiBuilders(String typeName) => _all(typeName);

/// [core.OpenUiView] with this package's defaults: Lucide icons, the bundled
/// Inter font, and links open in the browser.
class OpenUiView extends core.OpenUiView {
  const OpenUiView({
    super.key,
    required super.session,
    required super.builders,
    super.onToAssistant,
    super.onAction,
    super.queryLoader,
    super.child,
    super.fallbackServices = batteryServices,
    super.semanticsIdentifiers,
    super.fallback,
  });

  static core.OpenUiQueryState queryOf(BuildContext context) =>
      core.OpenUiView.queryOf(context);
}
