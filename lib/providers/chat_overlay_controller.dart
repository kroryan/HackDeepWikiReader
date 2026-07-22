import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'chat_provider.dart';
import 'settings_provider.dart';
import 'wiki_source.dart';

/// App-root chat session manager -- lives above the Navigator (see
/// main.dart's MaterialApp.builder + ChatOverlayHost) so a chat keeps
/// running across screen navigation. This mirrors how the web app's own
/// ChatWidget.tsx behaves: the underlying Ask component and its state are
/// never unmounted when the panel is "closed" -- only its visibility
/// toggles (`isOpen`), so reopening always shows the same conversation,
/// even mid-stream. Minimizing here works the same way: [minimize] only
/// hides the panel, it never disposes [chatProvider].
///
/// Holds at most one active session at a time -- opening a chat for a
/// different WikiSource disposes the previous one. Each WikiSource's
/// message history is still safe: ChatProvider persists every turn to Hive
/// keyed by WikiSource.sourceId, so reopening a previously-visited wiki's
/// chat restores its history even though the live ChatProvider instance
/// was recycled.
class ChatOverlayController extends ChangeNotifier {
  final SettingsProvider settings;
  ChatOverlayController(this.settings);

  WikiSource? _source;
  ChatProvider? _chatProvider;
  bool _open = false;
  bool _maximized = false;
  // True while a full-screen-ish overlay grown OUT of the chat panel is
  // showing (currently: the chat history bottom sheet) -- see
  // wiki_viewer_screen.dart's hideLinuxWebView, which is the only reader of
  // this. On Linux the .zim page is a real native WebKitGTK widget layered
  // above ALL of Flutter's own painting (see
  // third_party/webview_all_linux's plugin doc), so any Flutter overlay
  // that isn't accounted for by the chat panel's own reserved strip --
  // like a bottom sheet, which is full window width -- gets silently
  // painted over by whatever of that native widget is still visible,
  // exactly the same underlying issue the chat panel itself needed fixing
  // for. Nothing analogous is needed on Android/Windows: their WebView
  // widgets render as a normal Flutter Texture, so Flutter's own paint
  // order already puts any overlay on top correctly.
  bool _modalOpen = false;

  WikiSource? get source => _source;
  ChatProvider? get chatProvider => _chatProvider;
  bool get isOpen => _open;
  bool get isMaximized => _maximized;
  bool get hasSession => _chatProvider != null;
  bool get modalOpen => _modalOpen;

  void setModalOpen(bool value) {
    if (_modalOpen == value) return;
    _modalOpen = value;
    notifyListeners();
  }

  void openFor(WikiSource newSource, {String? currentPageId}) {
    AppLogger.instance.info('openFor sourceId=${newSource.sourceId} '
        'title="${newSource.title}" page=$currentPageId '
        'sameSource=${_source?.sourceId == newSource.sourceId} '
        'prevOpen=$_open hasProvider=${_chatProvider != null}');
    if (_source?.sourceId != newSource.sourceId) {
      _chatProvider?.removeListener(notifyListeners);
      _chatProvider?.dispose();
      try {
        _chatProvider = ChatProvider(source: newSource, settings: settings, currentPageId: currentPageId)
          ..addListener(notifyListeners);
        _source = newSource;
        AppLogger.instance.info('ChatProvider created ok, sessions=${_chatProvider!.sessions.length}');
      } catch (e, st) {
        AppLogger.instance.log('ERROR', 'ChatProvider constructor threw', error: e, stack: st);
        rethrow;
      }
    } else {
      _chatProvider?.setCurrentPageId(currentPageId ?? _chatProvider?.currentPageId);
    }
    _open = true;
    notifyListeners();
  }

  /// Keeps the open chat's context in sync with the page the user is
  /// currently reading, without switching sessions -- called as the user
  /// navigates pages inside the same wiki while chat stays attached.
  void updateCurrentPage(String sourceId, String? pageId) {
    if (_source?.sourceId == sourceId) {
      _chatProvider?.setCurrentPageId(pageId);
    }
  }

  /// Opens the chat for [newSource] if it isn't already showing for that
  /// source, or hides it if it is -- backs the per-wiki "Chat" action button
  /// so the same button both opens and minimizes the panel (matching the
  /// minimized bubble's tap-to-expand and the panel's own minimize button,
  /// which both already toggle visibility without disposing the session).
  void toggle(WikiSource newSource, {String? currentPageId}) {
    if (_open && _source?.sourceId == newSource.sourceId) {
      minimize();
    } else {
      openFor(newSource, currentPageId: currentPageId);
    }
  }

  void minimize() {
    _open = false;
    notifyListeners();
  }

  void expand() {
    if (_chatProvider != null) _open = true;
    notifyListeners();
  }

  void toggleMaximize() {
    _maximized = !_maximized;
    notifyListeners();
  }

  @override
  void dispose() {
    _chatProvider?.removeListener(notifyListeners);
    _chatProvider?.dispose();
    super.dispose();
  }
}
