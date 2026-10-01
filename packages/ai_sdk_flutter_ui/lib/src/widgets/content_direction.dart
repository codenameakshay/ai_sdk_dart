import 'package:flutter/widgets.dart';

final _firstLetter = RegExp(r'\p{L}', unicode: true);
final _rtlLetter = RegExp(
  r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF\u{10800}-\u{10FFF}\u{1E800}-\u{1EEFF}]',
  unicode: true,
);

/// The paragraph direction implied by [text]'s first letter, or null when it
/// has none, so the ambient [Directionality] applies.
///
/// Message content keeps its own direction: English text in an Arabic UI
/// must not be reordered, and vice versa. Not part of the public API.
TextDirection? contentDirection(String text) {
  final letter = _firstLetter.firstMatch(text)?[0];
  if (letter == null) return null;
  return _rtlLetter.hasMatch(letter) ? TextDirection.rtl : TextDirection.ltr;
}
