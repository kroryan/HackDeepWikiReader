# HackDeepWikiReader

A read-only companion client for [HackDeepWiki](https://github.com/kroryan/HackDeepWiki), for **Android, Linux, and Windows** from one Flutter codebase.

It never generates wikis and never triggers a security scan — those stay in the main HackDeepWiki app. What it does:

- **Connect to any HackDeepWiki server** by URL (your home server, a work instance, whatever you point it at) and browse its generated wikis.
- **Import `.zim` archives directly** and read/search/chat with them on the device. The archive parser, local loopback content server, page index and chat context all live in this app; no HackDeepWiki server is involved.
- **Read** the generated wiki pages, with the same section/page hierarchy the web app shows.
- **View Security Analysis / Website Security** reports — findings, severity breakdown, interactive graph, version history — for repos and websites alike.
- **Chat, fully independent of any HackDeepWiki server**: this app talks directly to your own configured LLM provider (Ollama, ChatGPT/OpenAI, any custom OpenAI-compatible endpoint, or Anthropic Claude — set these up under Settings) and builds its own context from the wiki content already loaded locally, rather than proxying through a backend. Toggle 🔐 "Security context" to fold the latest saved scan report into that context. Chat runs as a floating panel with a maximize toggle on Linux/Windows (mirroring the web app's own chat widget), and full-screen-but-minimizable on Android — the conversation keeps running in the background either way, even after leaving the wiki, until you send it a new message. This is the core of the app — everything else is in service of it.
- **Select and copy content** across complete wiki pages or chat transcripts; every user and assistant message also has its own copy button.
- **Open a `.hdwreader` bundle** — a portable, fully offline export produced by HackDeepWiki's web app (the "Export for HackDeepWikiReader" button, next to the Obsidian export) — for reading a wiki (optionally with its security report) with no server connection at all.

Imported `.zim` archives are parsed locally and served only to an in-app browser on `127.0.0.1`. Android uses its system WebView, Linux uses WebKitGTK and Windows uses WebView2, so archive HTML gets a real browser layout engine for its images, fonts, tables, flexbox and grid. JavaScript and external navigation stay disabled. Chat extracts the current ZIM page as plain text and sends it directly to the LLM provider configured in the reader, exactly like the other local wiki sources.

The reader keeps its database, imported ZIMs and logs in the platform's private application-support directory. On Linux this is normally `~/.local/share/com.kroryan.hackdeepwikireader/{data,zims,logs}`; affected older files are migrated out of `Documents` at startup.

## Getting the app

Every push to `main` publishes a rolling pre-release; tagged commits (`vX.Y.Z`) publish a stable release. All three platforms are built automatically by [`.github/workflows/release.yml`](.github/workflows/release.yml) — grab the latest build from the [Releases page](https://github.com/kroryan/HackDeepWikiReader/releases):

- **Linux** → `HackDeepWikiReader-linux-x64.tar.gz` (extract, run `bundle/hackdeepwikireader`)
- **Windows** → `HackDeepWikiReader-windows-x64.zip` (extract, run `hackdeepwikireader.exe`)
- **Android** → `HackDeepWikiReader.apk` (enable "install from unknown sources" if prompted)

## Building from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) plus, per target:

- **Linux desktop**: `clang cmake ninja-build pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev libsoup-3.0-dev liblzma-dev libstdc++-12-dev`
- **Android**: Android SDK (cmdline-tools, platform-tools, `platforms;android-34`, `build-tools;34.0.0`) and a JDK 17 or 21 (not a bleeding-edge JDK — the Android Gradle Plugin doesn't yet support them)
- **Windows**: Visual Studio with the "Desktop development with C++" workload

```bash
flutter pub get
flutter analyze
flutter test

flutter build linux --release     # build/linux/x64/release/bundle/
flutter build windows --release   # build/windows/x64/runner/Release/
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release # build/app/outputs/bundle/release/app-release.aab
```

The Linux runner creates its `GtkOverlay` before Flutter's GL view is realized, then hosts WebKitGTK there. This preserves the archive's browser layout without the X11/GLX crash caused by reparenting an already-running Flutter view.

## Architecture

```
lib/
  api/            REST client for a connected HackDeepWiki backend --
                   read-only browsing of its wikis and .zim archives. Chat
                   never goes through this: see llm/ below.
  llm/             This app's own, independent LLM clients -- Ollama,
                   OpenAI-compatible (covers ChatGPT/OpenAI and any custom
                   endpoint), Anthropic Claude -- plus the context builder
                   that turns locally-loaded wiki content (+ optionally the
                   security report) into the prompt sent to whichever
                   provider the user picks. None of this talks to a
                   HackDeepWiki server.
  bundle/          .hdwreader offline bundle parser (unzip + manifest.json).
  zim/             Native Dart ZIM parser plus a loopback-only HTTP server
                   used by the platform WebView. Archives, redirects and
                   compressed clusters are read without a backend.
  models/          Plain Dart data classes mirroring the backend's Pydantic
                   models / the web app's TypeScript types field-for-field,
                   plus this app's own LlmConnection/AppSettings models.
  providers/       ChangeNotifier state: the library (saved endpoints +
                   imported bundles), the WikiSource abstraction that lets
                   every screen work identically against a live server or
                   an offline bundle, this app's own LLM/appearance
                   settings, per-wiki chat state, and the app-root
                   ChatOverlayController that keeps a chat session alive
                   across navigation/minimize (see widgets/chat_overlay_host.dart).
  screens/         One file per screen -- home (library), add/edit
                   endpoint, project list, wiki viewer, security analysis,
                   settings, add/edit LLM provider. Chat has no screen of
                   its own -- it's the global overlay below.
  storage/         Local persistence (Hive) -- plain JSON maps, no
                   generated TypeAdapters, so adding a field to any model
                   never needs a codegen step.
  theme/           Ports deepwiki-open's "Cyberpunk Hacker" design tokens
                   (src/app/globals.css) into light/dark Flutter themes,
                   parameterized by the user's chosen font/size (Settings).
  widgets/         Shared widgets -- page tree, 2D vulnerability graph, and
                   ChatOverlayHost: the always-mounted chat panel/bubble
                   that sits above the Navigator (see main.dart) so a
                   running chat survives navigating away or minimizing it.
```

To add a new read-only feature: add one method to `lib/api/hackdeepwiki_client.dart` that mirrors an existing `api/api.py` endpoint, consume it from a provider, and build a screen. No existing file needs to change for that. To support another content source (alongside a live server, an offline bundle and a local ZIM), implement `WikiSource` (`lib/providers/wiki_source.dart`) -- every screen below the library already only depends on that interface. To add another LLM provider, implement `LlmClient` (`lib/llm/llm_client.dart`) in its own file and add one case to `buildLlmClient` -- nothing else needs to change.
