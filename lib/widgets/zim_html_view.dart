import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../providers/wiki_source.dart';
import '../theme/app_theme.dart';

/// Renders one .zim entry's raw HTML -- the native-Flutter counterpart to
/// the web app's `<iframe sandbox="">` around /api/zim/{id}/entry (see
/// src/app/zim/[id]/page.tsx): same intent (show the archive's own HTML
/// as-is, never execute its scripts), same reason (some archives ship a
/// client-side app that assumes capabilities an opaque frame doesn't have
/// and crashes without them). flutter_html never executes `<script>` at
/// all, so that guarantee comes for free here.
///
/// Internal `<img>`/`<a>` references are resolved against the *current*
/// entry's own path (ZIM links are always relative, like a normal
/// filesystem/URL) and re-fetched straight from the archive -- nothing
/// goes over the network.
class ZimHtmlView extends StatelessWidget {
  final ZimWikiSource source;
  final String path;
  final String html;
  final ValueChanged<String> onNavigate;

  const ZimHtmlView({
    super.key,
    required this.source,
    required this.path,
    required this.html,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Html(
          data: html,
          onLinkTap: (href, _, __) {
            if (href == null || href.isEmpty || href.startsWith('#')) return;
            final uri = Uri.tryParse(href);
            // External links (http/https/mailto/...) open nowhere -- this is
            // a fully offline reader with no browser to hand them to. Only
            // same-archive relative links are navigable.
            if (uri != null && uri.hasScheme) return;
            final resolved = ZimWikiSource.resolvePath(path, href);
            if (resolved.isNotEmpty) onNavigate(resolved);
          },
          extensions: [
            // NOT ImageExtension: its `matches()` only claims http(s)/asset:/
            // data: sources (see ImageBuiltIn.matches in the flutter_html
            // source) -- a .zim's <img src="../../assets/logo.png"> is none
            // of those, so that extension silently never fires and the
            // image renders as nothing. TagExtension has no such src-scheme
            // filter: it claims every <img>, which is exactly right here,
            // since every image reference in a .zim's HTML is a relative
            // in-archive path resolved the same way as links (below).
            TagExtension(
              tagsToExtend: {'img'},
              builder: (extensionContext) {
                final src = extensionContext.attributes['src'];
                if (src == null || src.isEmpty) return const SizedBox.shrink();
                final resolved = ZimWikiSource.resolvePath(path, src);
                return FutureBuilder(
                  future: source.loadAsset(resolved),
                  builder: (context, snapshot) {
                    // A zero-size (or invisible) placeholder here, combined
                    // with a page whose own CSS paints a dark full-bleed
                    // background (real .zim pages do this -- see the
                    // "nothing renders" bug this was fixed for), makes a
                    // whole image grid look like a blank black rectangle
                    // instead of "images still loading/unavailable". A
                    // visible placeholder box means something always
                    // renders even when an image never resolves.
                    if (snapshot.connectionState != ConnectionState.done || snapshot.data == null) {
                      return Container(width: 48, height: 48, color: Theme.of(context).cardColor);
                    }
                    return Image.memory(
                      snapshot.data!,
                      errorBuilder: (_, __, ___) =>
                          Container(width: 48, height: 48, color: Theme.of(context).cardColor),
                    );
                  },
                );
              },
            ),
          ],
          style: {
            'body': Style(color: Theme.of(context).appColors.foreground, backgroundColor: Colors.transparent),
            'html': Style(backgroundColor: Colors.transparent),
            // Real .zim pages (verified: a Wikipedia mobile-main-page
            // layout) set a full-bleed dark `background` on generic layout
            // wrapper ids expecting a real browser's viewport-filling body
            // -- without that, it just paints over the reader's own
            // background/text with nothing else compensating, and the page
            // looks blank. flutter_html applies these custom style entries
            // AFTER the page's own CSS (html_parser.dart's styleTree merges
            // "custom styles" last), so this reliably wins.
            '#container': Style(backgroundColor: Colors.transparent),
            '#content': Style(backgroundColor: Colors.transparent),
            'a': Style(color: Theme.of(context).colorScheme.primary),
            'pre': Style(
              backgroundColor: Theme.of(context).cardColor,
              padding: HtmlPaddings.all(8),
            ),
            'code': Style(backgroundColor: Theme.of(context).cardColor, fontFamily: 'monospace'),
          },
          doNotRenderTheseTags: const {'script', 'style', 'iframe', 'form'},
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Reader-mode rendering: close to the real page, not pixel-identical -- complex layouts '
            '(tables, multi-column grids) may look plainer than in a full browser.',
            style: TextStyle(fontSize: 11, color: muted, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}
