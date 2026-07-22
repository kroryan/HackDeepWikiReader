import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_theme.dart';

/// Wiki page Markdown renderer -- MarkdownBody plus a custom `pre` (fenced
/// code block) builder, matching the web app's Markdown.tsx treatment:
/// syntax-highlighted code with a language/copy header for regular code
/// fences, and a distinctly-labeled block for ```mermaid fences.
///
/// Mermaid diagrams aren't rendered as actual diagrams here -- that needs a
/// JS engine (mermaid.js), which means a WebView, and this app deliberately
/// avoids WebView everywhere else for cross-platform reliability (see
/// README's `.zim` section for the same tradeoff, made for the same
/// reason). Until that's worth revisiting, the raw Mermaid source is at
/// least shown clearly -- labeled and monospaced -- instead of rendering as
/// unstyled, easy-to-miss text mixed into the surrounding prose.
class WikiMarkdownView extends StatelessWidget {
  final String data;

  /// Whether the rendered text is selectable. Defaults true -- but the chat
  /// overlay (lib/widgets/chat_overlay_host.dart) passes false, because the
  /// chat panel is a sibling of the Navigator (see main.dart's
  /// MaterialApp.builder) and so has no Overlay ancestor, while selectable
  /// text uses an OverlayPortal for its selection handles/toolbar. With no
  /// Overlay up the tree that throws "No Overlay widget found" on the first
  /// repaint and blanks the panel. The wiki *page* viewer lives under the
  /// Navigator (has an Overlay), so it keeps selectable true.
  final bool selectable;

  const WikiMarkdownView({super.key, required this.data, this.selectable = true});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MarkdownBody(
      data: data,
      selectable: selectable,
      builders: {'pre': _CodeBlockBuilder(isDark: isDark)},
      onTapLink: (text, href, title) {
        // External links only (no local repo file browsing in this app).
      },
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;
  _CodeBlockBuilder({required this.isDark});

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    md.Element? codeElement;
    for (final child in element.children ?? const []) {
      if (child is md.Element && child.tag == 'code') {
        codeElement = child;
        break;
      }
    }
    final rawClass = codeElement?.attributes['class'] ?? '';
    final language = rawClass.startsWith('language-') ? rawClass.substring('language-'.length) : '';
    final source = (codeElement ?? element).textContent;
    final colors = Theme.of(context).appColors;

    if (language == 'mermaid') {
      return _DiagramSourceBlock(source: source, colors: colors);
    }
    return _CodeBlock(source: source, language: language, isDark: isDark, colors: colors);
  }
}

class _CodeBlock extends StatelessWidget {
  final String source;
  final String language;
  final bool isDark;
  final AppColors colors;

  const _CodeBlock({required this.source, required this.language, required this.isDark, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282C34) : colors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.borderColor))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? 'code' : language.toUpperCase(),
                    style: TextStyle(fontSize: 11, color: colors.muted, letterSpacing: 0.5),
                  ),
                ),
                InkWell(
                  onTap: () => Clipboard.setData(ClipboardData(text: source)),
                  child: Icon(Icons.copy, size: 14, color: colors.muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: HighlightView(
                source,
                language: language.isEmpty ? 'plaintext' : language,
                theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
                padding: const EdgeInsets.all(10),
                textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagramSourceBlock extends StatelessWidget {
  final String source;
  final AppColors colors;

  const _DiagramSourceBlock({required this.source, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.accentSecondary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 14, color: colors.accentSecondary),
              const SizedBox(width: 6),
              Text(
                'DIAGRAM (Mermaid source -- rendering not yet supported)',
                style: TextStyle(fontSize: 11, color: colors.accentSecondary, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(source, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }
}
