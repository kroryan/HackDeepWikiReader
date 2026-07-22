import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/chat_models.dart';
import '../navigation.dart';
import '../providers/chat_overlay_controller.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/settings_screen.dart';
import '../theme/app_theme.dart';
import 'wiki_markdown_view.dart';

bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

/// Always-mounted overlay (see main.dart's MaterialApp.builder) rendering
/// the chat FAB/bubble + panel above whatever screen is currently showing.
/// A single widget instance backs the whole lifetime of an active chat
/// session, so minimizing/maximizing/navigating away never tears down the
/// ChatProvider or interrupts an in-flight answer -- see
/// ChatOverlayController for the session-lifecycle side of this.
///
/// Desktop (Linux/Windows): small floating panel by default, with a
/// maximize toggle -- mirrors the web app's ChatWidget.tsx exactly (FAB,
/// panel, expand/compress, close-which-is-really-minimize).
/// Android: opens full-screen (a small floating panel isn't usable at
/// phone sizes) but stays minimizable -- minimizing shows a small floating
/// bubble instead, tap to return to full-screen, same session still
/// running underneath the whole time.
///
/// How it's mounted: this widget sits ALONGSIDE the root Navigator in
/// MaterialApp.builder's Stack (so it paints above the app, and being a
/// separate Navigator instance means it's untouched by route push/pop
/// underneath -- the chat stays alive across navigation, the original
/// design). It's its OWN [Navigator]: the chat content is the Navigator's
/// single home route, a non-modal [OverlayRoute] (no ModalBarrier, so it
/// doesn't block taps on the app behind the panel). That gives the content
/// both a Navigator ancestor (so the toolbar's DropdownButton / the
/// History bottom sheet can push their popup/modal routes) and an Overlay
/// ancestor (so the panel's tooltips, the composer TextField, and markdown
/// selection can use OverlayPortal without "No Overlay widget found").
/// `Positioned` panels float via the inner Navigator's overlay (a
/// Stack-like theater); the home route is non-opaque so empty areas pass
/// hits through to the app underneath.
class ChatOverlayHost extends StatelessWidget {
  const ChatOverlayHost({super.key});

  @override
  Widget build(BuildContext context) {
    // HeroControllerScope.none(): without this, this Navigator inherits the
    // app root Navigator's default HeroController (Flutter installs one
    // automatically per MaterialApp) and Flutter refuses to let two
    // Navigators share one -- "A HeroController can not be shared by
    // multiple Navigators" (seen live, via AppLogger's FlutterError.onError
    // capture). The chat panel never does hero-animated route transitions,
    // so it doesn't need a controller of its own either -- `.none()` is the
    // correct fix, not just a workaround.
    return HeroControllerScope.none(
      child: Navigator(
        initialRoute: '/',
        onGenerateRoute: (settings) =>
            _ChatHomeRoute(builder: (_) => const _ChatOverlayContent()),
        // The chat is a floating overlay, never a focus-trap that dims the app
        // behind it; keep its own focus management out of the way.
        observers: const <NavigatorObserver>[],
      ),
    );
  }
}

/// Non-modal home route for the chat's private Navigator -- renders only the
/// chat content as a single non-opaque [OverlayEntry], with NO barrier (a
/// [ModalRoute] would install a full-screen [ModalBarrier] that blocks the
/// app behind the panel). Popup/modal routes the content pushes on top
/// (the toolbar DropdownButton's menu, the History bottom sheet) DO get
/// their own transient barriers, which is correct and expected for menus.
class _ChatHomeRoute extends OverlayRoute<void> {
  _ChatHomeRoute({required this.builder})
    : super(settings: const RouteSettings(name: '/'));
  final WidgetBuilder builder;

  @override
  Iterable<OverlayEntry> createOverlayEntries() sync* {
    yield OverlayEntry(opaque: false, builder: builder);
  }
}

/// The actual visible chat UI -- rendered as the home route of the chat's
/// private Navigator, so it (and everything it builds: dropdowns, tooltips,
/// the composer TextField, markdown selection) has Navigator + Overlay
/// ancestors.
class _ChatOverlayContent extends StatelessWidget {
  const _ChatOverlayContent();

  @override
  Widget build(BuildContext context) {
    final overlay = context.watch<ChatOverlayController>();
    if (!overlay.hasSession) {
      return const SizedBox.shrink();
    }

    if (!overlay.isOpen) {
      return _MinimizedBubble(overlay: overlay);
    }
    return _isAndroid
        ? _AndroidFullscreenPanel(overlay: overlay)
        : _DesktopPanel(overlay: overlay);
  }
}

class _MinimizedBubble extends StatelessWidget {
  final ChatOverlayController overlay;
  const _MinimizedBubble({required this.overlay});

  @override
  Widget build(BuildContext context) {
    final chat = overlay.chatProvider!;
    return Positioned(
      bottom: 24,
      right: 24,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: overlay.expand,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).appColors.accentPrimary,
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 16),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.chat_bubble, color: Colors.black),
                  if (chat.isLoading)
                    const Positioned(
                      right: 4,
                      top: 4,
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopPanel extends StatelessWidget {
  final ChatOverlayController overlay;
  const _DesktopPanel({required this.overlay});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Positioned(
      bottom: overlay.isMaximized ? 32 : 24,
      right: overlay.isMaximized ? 32 : 24,
      top: overlay.isMaximized ? 32 : null,
      left: overlay.isMaximized ? 32 : null,
      width: overlay.isMaximized ? null : 420,
      height: overlay.isMaximized ? null : 640,
      // A BoxShadow on a plain DecoratedBox instead of Material(elevation:
      // ...) -- PhysicalModel-based elevation shadows are a known trigger
      // for repaint/compositing glitches (a gray/blank flash that only
      // clears on the next interaction) in the Flutter Linux GTK embedder
      // when running without a compositing window manager. The inner
      // Material(type: transparency) is still needed -- it's what lets
      // buttons/inputs inside find an ink-splash ancestor -- but that type
      // skips the PhysicalModel paint entirely, unlike a default/elevated
      // Material.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.cardBg,
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                Container(height: 3, color: colors.accentPrimary),
                _PanelHeader(
                  title: overlay.source?.title ?? 'Chat',
                  onMaximizeToggle: overlay.toggleMaximize,
                  isMaximized: overlay.isMaximized,
                  onClose: overlay.minimize,
                ),
                const Expanded(child: _ChatPanelBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AndroidFullscreenPanel extends StatelessWidget {
  final ChatOverlayController overlay;
  const _AndroidFullscreenPanel({required this.overlay});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Positioned.fill(
      child: Material(
        color: colors.background,
        child: SafeArea(
          child: Column(
            children: [
              _PanelHeader(
                title: overlay.source?.title ?? 'Chat',
                isMaximized: true,
                onClose: overlay.minimize,
                closeIcon: Icons.keyboard_arrow_down,
                closeTooltip: 'Minimize',
              ),
              const Expanded(child: _ChatPanelBody()),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final bool isMaximized;
  final VoidCallback? onMaximizeToggle;
  final VoidCallback onClose;
  final IconData closeIcon;
  final String closeTooltip;

  const _PanelHeader({
    required this.title,
    required this.isMaximized,
    this.onMaximizeToggle,
    required this.onClose,
    this.closeIcon = Icons.remove,
    this.closeTooltip = 'Minimize',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderColor)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.chat_bubble_outline,
            color: colors.accentPrimary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (onMaximizeToggle != null)
            IconButton(
              icon: Icon(
                isMaximized ? Icons.close_fullscreen : Icons.open_in_full,
                size: 18,
              ),
              tooltip: isMaximized ? 'Restore' : 'Maximize',
              onPressed: onMaximizeToggle,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            icon: Icon(closeIcon, size: 20),
            tooltip: closeTooltip,
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ChatPanelBody extends StatefulWidget {
  const _ChatPanelBody();

  @override
  State<_ChatPanelBody> createState() => _ChatPanelBodyState();
}

class _ChatPanelBodyState extends State<_ChatPanelBody> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlay = context.watch<ChatOverlayController>();
    final settings = context.watch<SettingsProvider>();
    final chat = overlay.chatProvider;
    if (chat == null) return const SizedBox.shrink();

    if (settings.connections.isEmpty) {
      return _NoProviderNotice(colors: Theme.of(context).appColors);
    }

    return ChangeNotifierProvider<ChatProvider>.value(
      value: chat,
      child: Consumer<ChatProvider>(
        builder: (context, chat, _) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
          return Column(
            children: [
              _buildToolbar(context, chat, settings),
              Expanded(
                // One selection registrar for the complete transcript lets
                // a drag selection continue across several user/assistant
                // messages instead of stopping at each bubble boundary.
                child: SelectionArea(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final m in chat.activeSession.messages)
                        _MessageBubble(message: m),
                      if (chat.isLoading && chat.thinkingBuffer.isNotEmpty)
                        _ThinkingPanel(text: chat.thinkingBuffer),
                      if (chat.isLoading && chat.toolStatus != null)
                        _ToolStatusBubble(text: chat.toolStatus!),
                      if (chat.isLoading && chat.toolStatus == null)
                        _MessageBubble.streaming(text: chat.streamingAnswer),
                      if (chat.error != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            chat.error!,
                            style: TextStyle(
                              color: Theme.of(context).appColors.highlight,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _buildComposer(context, chat),
            ],
          );
        },
      ),
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    ChatProvider chat,
    SettingsProvider settings,
  ) {
    final active = chat.activeConnection;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: active?.id,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final c in settings.connections)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: chat.setConnection,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: 'New chat',
                onPressed: chat.newChat,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'History',
                onPressed: () => _showHistorySheet(context, chat),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (chat.securityContextAvailable)
            FilterChip(
              label: const Text('🔐 Security context'),
              selected: chat.includeSecurityContext,
              onSelected: chat.setIncludeSecurityContext,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  void _showHistorySheet(BuildContext context, ChatProvider chat) {
    // On Linux the open .zim page is a real native WebKitGTK widget layered
    // above ALL Flutter painting (see third_party/webview_all_linux), and
    // only the chat panel's own reserved strip accounts for it -- a bottom
    // sheet is full window width, so without this the native widget just
    // keeps covering whatever part of the sheet falls outside that strip,
    // same underlying issue useRootNavigator alone doesn't touch. Captured
    // once up front (not re-read via context after the await below) and
    // cleared in .whenComplete regardless of how the sheet closes.
    final overlay = context.read<ChatOverlayController>();
    overlay.setModalOpen(true);
    showModalBottomSheet(
      context: context,
      // The chat panel lives inside its OWN small private Navigator (see
      // this file's top doc comment) so it stays alive across app
      // navigation -- but that also means showModalBottomSheet's default
      // Navigator.of(context) lookup finds THAT nested Navigator, not the
      // app's real root one. Its Overlay is boxed into the floating panel's
      // own small, rounded, fixed-size area (420x640 unless maximized), so
      // the sheet was rendering (and clipping) inside that tiny box instead
      // of the actual window -- unreadable, and its delete buttons
      // unreachable, for any session list past the first couple of items.
      // useRootNavigator escapes to the app's real root Navigator instead,
      // which owns the whole window.
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final session in chat.sessions)
                ListTile(
                  title: Text(session.title, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${session.messages.length} messages'),
                  onTap: () {
                    chat.selectSession(session.id);
                    Navigator.of(sheetContext).pop();
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => chat.deleteSession(session.id),
                  ),
                ),
            ],
          ),
        );
      },
    ).whenComplete(() => overlay.setModalOpen(false));
  }

  Widget _buildComposer(BuildContext context, ChatProvider chat) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Ask about this wiki…',
                ),
                onSubmitted: (_) => _send(chat),
                enabled: !chat.isLoading,
                minLines: 1,
                maxLines: 4,
              ),
            ),
            IconButton(
              // While loading this becomes a stop button instead of a
              // disabled spinner -- a stalled connection (see
              // llmStreamStallTimeout) can take up to that long to time
              // itself out on its own, and the user shouldn't be stuck
              // staring at a spinner with no way out until then.
              icon: chat.isLoading
                  ? const Icon(Icons.stop_circle_outlined)
                  : const Icon(Icons.send),
              tooltip: chat.isLoading ? 'Stop' : 'Send',
              onPressed: chat.isLoading ? chat.cancel : () => _send(chat),
            ),
          ],
        ),
      ),
    );
  }

  void _send(ChatProvider chat) {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    chat.sendMessage(text);
  }
}

class _NoProviderNotice extends StatelessWidget {
  final AppColors colors;
  const _NoProviderNotice({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.settings_suggest_outlined,
              size: 40,
              color: colors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              'No LLM provider configured yet.\nGo to Settings to add one before you can chat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
              onPressed: () => rootNavigatorKey.currentState?.push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live reasoning/"thinking" text a provider streams separately from the
/// answer (see LlmClient.streamChat's onThinking doc and
/// ChatProvider.thinkingBuffer) -- collapsed by default like every other
/// AI chat UI's reasoning panel, expandable if the user wants to follow
/// along. Existing purely so a model that's genuinely still working (just
/// slowly, mid chain-of-thought, which can run long on a broad question)
/// doesn't look indistinguishable from a dead one -- previously this text
/// was dropped entirely and the user saw nothing but a bare spinner.
class _ThinkingPanel extends StatelessWidget {
  final String text;
  const _ThinkingPanel({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderColor),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: const SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text(
            'Thinking…',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: colors.muted,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the streaming answer bubble while the agentic loop
/// (see ChatProvider._streamOneRound/searchWiki) is running a SEARCH_WIKI
/// tool round -- makes it visible that a search is happening instead of
/// looking like the answer has stalled.
class _ToolStatusBubble extends StatelessWidget {
  final String text;
  const _ToolStatusBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.inputBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: colors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String role;
  final String text;

  _MessageBubble({required ChatMessage message})
    : role = message.role,
      text = message.content;

  const _MessageBubble.streaming({required this.text}) : role = 'assistant';

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final colors = Theme.of(context).appColors;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: isUser
              ? colors.accentPrimary.withValues(alpha: 0.15)
              : colors.inputBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderColor),
        ),
        child: text.isEmpty
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isUser ? 'You' : 'Assistant',
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        tooltip: 'Copy message',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: text)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (isUser)
                    Text(text)
                  else
                    WikiMarkdownView(data: text, selectable: false),
                ],
              ),
      ),
    );
  }
}
