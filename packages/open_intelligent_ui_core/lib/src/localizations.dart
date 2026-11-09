import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';

/// Every user-visible string of the Open Intelligent UI packages, in English.
/// Subclass it and override the getters to translate, then register an
/// [OpenUiLocalizationsDelegate] in `localizationsDelegates`.
class OpenUiLocalizations {
  const OpenUiLocalizations();

  static OpenUiLocalizations of(BuildContext context) =>
      Localizations.of<OpenUiLocalizations>(context, OpenUiLocalizations) ??
      const OpenUiLocalizations();

  static const LocalizationsDelegate<OpenUiLocalizations> delegate =
      OpenUiLocalizationsDelegate();

  // core
  String get loadingData => 'Loading data';
  String get untitledArtifact => 'Untitled artifact';
  String artifactTitle(String title, {required bool generating}) =>
      generating ? '$title (generating…)' : title;
  String closeArtifact(String title) => 'Close $title';
  String get copyCode => 'Copy code';
  String get copy => 'Copy';
  String get copied => 'Copied';
  String get previous => 'Previous';
  String get next => 'Next';
  String get sliderValue => 'Value';
  String get date => 'Date';
  String get done => 'Done';
  String get choose => 'Choose…';
  String get tapToFlip => 'Tap to flip';
  String get timer => 'Timer';
  String get start => 'Start';
  String get pause => 'Pause';
  String get resume => 'Resume';
  String get reset => 'Reset';
  String chartLabel(String type, String series, String x) =>
      '$type chart of $series by $x';
  String get chartValues => 'values';
  String get confirm => 'Confirm';
  String get cancel => 'Cancel';
  String get actionFailed => 'Something went wrong. Try again.';

  /// A write cut off by a restore while the host checks whether it went through.
  String get checkingAction => 'Checking…';

  // web package
  String get interactiveView => 'Interactive view';
  String get preparingInteractiveView => 'Preparing the interactive view…';
  String get interactiveViewUnsupported =>
      'This interactive view runs on Android, iOS, macOS and the web.';
  String get youTubeVideo => 'YouTube video';
  String playVideo(String label) => 'Play $label';

  // maps package
  String get map => 'Map';
  String get filterPlaces => 'Filter places';
  String get allPlaces => 'All places';
  String get streetRouteLoaded => 'Street route loaded.';
  String get streetRouteUnavailable =>
      'Street routing unavailable. Showing direct connections.';
  String get streetRouteLoading => 'Street route loading.';
  String get routeNoteStreets =>
      ' The line follows streets; it is an overview, not turn-by-turn directions.';
  String get routeNoteDirect =>
      ' The line joins the places in order. Street routing is loading or unavailable.';
  String get twoFingerPan => 'Use two fingers to move the map';
  String get showEveryPlace => 'Show every place';
  String get aboutThisMap => 'About this map';
  String get expand => 'Expand';
  String get collapse => 'Collapse';
  String get zoomIn => 'Zoom in';
  String get zoomOut => 'Zoom out';
  String mapHelp(String routeNote) =>
      'Drag to explore and use + and − to zoom. Select a place to highlight it.$routeNote';
  String get routeOverview => 'Route overview';
  String get mapTilesUnavailable =>
      'Map tiles are temporarily unavailable. The places are still shown.';

  // chat package
  String formData(int fields) =>
      'Form data ($fields ${fields == 1 ? 'field' : 'fields'})';
}

/// Serves [OpenUiLocalizations] for each language code in [byLanguage]; any
/// other locale gets the English base.
final class OpenUiLocalizationsDelegate
    extends LocalizationsDelegate<OpenUiLocalizations> {
  const OpenUiLocalizationsDelegate([this.byLanguage = const {}]);

  /// Translations keyed by language code.
  final Map<String, OpenUiLocalizations> byLanguage;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<OpenUiLocalizations> load(Locale locale) => SynchronousFuture(
    byLanguage[locale.languageCode] ?? const OpenUiLocalizations(),
  );

  @override
  bool shouldReload(OpenUiLocalizationsDelegate old) =>
      !identical(byLanguage, old.byLanguage);
}
