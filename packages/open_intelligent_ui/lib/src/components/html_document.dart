// The page runs isolated: scripts only, no access to the app, no navigation
// away. Its CSP allows inline code and a few script CDNs and no other network.
const _cdns =
    'https://cdn.jsdelivr.net https://unpkg.com https://cdnjs.cloudflare.com https://esm.sh';

/// The reference's Content Security Policy for `HtmlView` pages.
const htmlViewCsp =
    "default-src 'none'; "
    "script-src 'unsafe-inline' $_cdns; "
    "style-src 'unsafe-inline' $_cdns https://fonts.googleapis.com; "
    'font-src https://fonts.gstatic.com data:; '
    'img-src data: blob: https:; '
    'media-src data: blob:; '
    'connect-src $_cdns; '
    "frame-src 'none'; "
    "form-action 'none'; "
    "base-uri 'none'";

const htmlViewMinHeight = 80.0;
const htmlViewMaxHeight = 2400.0;
const htmlViewStartHeight = 360.0;

/// How the page reports its content height: to a JavaScript channel on
/// native web views, or to the parent window on the web.
enum HeightReport { channel, parent }

// The reference frame is sandboxed without allow-same-origin: an opaque
// origin, so storage, cookies and service workers fail and dialogs and
// popups do nothing. A native page gets the same: it runs only if its
// origin is opaque (else the rest of the document becomes inert text), and
// these APIs fail as they do in that frame.
const _sandbox =
    r'''<script>(function(){"use strict";if(self.origin!=="null"){document.write("<plaintext hidden>");return}function err(){return new DOMException("The document is sandboxed and lacks the 'allow-same-origin' flag.","SecurityError")}function no(){throw err()}function later(){return Promise.reject(err())}function lock(o,n,d){d.configurable=false;try{Object.defineProperty(o,n,d)}catch(e){}}function deny(o,n){lock(o,n,{get:no,set:no})}function stub(o,n,v){lock(o,n,{get:function(){return v}})}function put(o,n,v){lock(o,n,{value:v,writable:true})}deny(window,"localStorage");deny(window,"sessionStorage");deny(Document.prototype,"cookie");deny(Navigator.prototype,"serviceWorker");stub(window,"indexedDB",Object.freeze({open:no,deleteDatabase:no,cmp:no,databases:later}));stub(window,"caches",Object.freeze({open:later,has:later,delete:later,keys:later,match:later}));stub(Navigator.prototype,"storage",Object.freeze({estimate:later,persist:later,persisted:later,getDirectory:later}));put(window,"BroadcastChannel",class BroadcastChannel extends EventTarget{constructor(name){super();this.name=String(name);this.onmessage=null;this.onmessageerror=null}postMessage(){}close(){}});put(window,"open",function(){return null});put(window,"alert",function(){});put(window,"confirm",function(){return false});put(window,"prompt",function(){return null});put(window,"print",function(){})})()</script>''';

// The reference's reporter, word for word on the web; native pages post to
// the IuiHeight channel and have no parent to ask them to measure again.
String _reporter(HeightReport to) => switch (to) {
  HeightReport.parent =>
    '<script>(function(){var last=0;function send(){var h=Math.ceil(document.documentElement.getBoundingClientRect().height);if(Math.abs(h-last)>1){last=h;parent.postMessage({type:"iui-html-view-height",height:h},"*")}}addEventListener("message",function(e){if(e.source===parent&&e.data==="iui-html-view-measure"){last=0;send()}});addEventListener("load",send);new ResizeObserver(send).observe(document.documentElement);send()})()</script>',
  HeightReport.channel =>
    '<script>(function(){var last=0;function send(){var h=Math.ceil(document.documentElement.getBoundingClientRect().height);if(Math.abs(h-last)>1){last=h;if(window.IuiHeight)IuiHeight.postMessage(String(h))}}addEventListener("load",send);new ResizeObserver(send).observe(document.documentElement);send()})()</script>',
};

/// The page around the model's [html]: the policy first, so it covers all of
/// the model's markup.
String htmlViewDocument(
  String html, {
  required bool dark,
  required HeightReport report,
}) =>
    '<!doctype html><meta charset="utf-8">'
    '<meta http-equiv="Content-Security-Policy" content="$htmlViewCsp">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<style>:root{color-scheme:${dark ? 'dark' : 'light'}}html,body{margin:0}'
    'body{font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}</style>'
    '${report == HeightReport.channel ? _sandbox : ''}'
    '${_reporter(report)}$html';

/// A reported height, clamped; null when it is not a finite number.
double? clampHeight(Object? value) {
  final h = value is num ? value.toDouble() : double.tryParse('$value');
  if (h == null || !h.isFinite) return null;
  return h.clamp(htmlViewMinHeight, htmlViewMaxHeight);
}

final _youTube = RegExp(
  r'(?:youtu\.be\/|[?&]v=|\/embed\/|\/shorts\/)([\w-]{11})|^([\w-]{11})$',
);

/// The 11-character id in a YouTube id or URL, or null.
String? youTubeId(String value) {
  final m = _youTube.firstMatch(value.trim());
  return m?.group(1) ?? m?.group(2);
}

/// Hosts a YouTube embed may navigate within.
bool isYouTubeHost(String host) => const [
  'youtube-nocookie.com',
  'youtube.com',
  'ytimg.com',
  'googlevideo.com',
  'ggpht.com',
  'gstatic.com',
  'google.com',
].any((d) => host == d || host.endsWith('.$d'));
