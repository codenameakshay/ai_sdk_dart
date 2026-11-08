//
// The icon outlines below are Lucide's, under this licence:
//
// ISC License
//
// Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2023 as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2025.
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//
// ---
//
// The MIT License (MIT) (for portions derived from Feather)
//
// Copyright (c) 2013-2023 Cole Bemis
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Copied from lucide_icons.dart; umbrella_test checks they match.

/// The icons core draws without a resolver: lucide outlines, copied verbatim.
const Map<String, (String, String?)> builtinGlyphs = {
  'app-window': (
    'M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2Z|M10 4v4|M2 8h20|M6 4v4',
    null,
  ),
  'arrow-up-right': ('M7 7h10v10|M7 17 17 7', null),
  'calendar': (
    'M8 2v4|M16 2v4|M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2Z|M3 10h18',
    null,
  ),
  'check': ('M20 6 9 17l-5-5', null),
  'chevron-down': ('m6 9 6 6 6-6', null),
  'chevron-left': ('m15 18-6-6 6-6', null),
  'chevron-right': ('m9 18 6-6-6-6', null),
  'copy': (
    'M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2Z|M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2',
    null,
  ),
  'expand': (
    'm15 15 6 6|m15 9 6-6|M21 16v5h-5|M21 8V3h-5|M3 16v5h5|m3 21 6-6|M3 8V3h5|M9 9 3 3',
    null,
  ),
  'image': (
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2Z|M7 9a2 2 0 1 0 4 0a2 2 0 1 0 -4 0Z|m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21',
    null,
  ),
  'info': (
    'M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0Z|M12 16v-4|M12 8h.01',
    null,
  ),
  'navigation': ('M3 11L22 2L13 21L11 13L3 11Z', null),
  'play': (
    'M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z',
    null,
  ),
};
