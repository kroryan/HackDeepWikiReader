# HackDeepWikiReader

A read-only companion client for [HackDeepWiki](https://github.com/kroryan/HackDeepWiki), for **Android, Linux, and Windows** from one Flutter codebase.

It never generates wikis and never triggers a security scan — those stay in the main HackDeepWiki app. What it does:

- **Connect to any HackDeepWiki server** by URL (your home server, a work instance, whatever you point it at) and browse every wiki and `.zim` archive cached there.
- **Read** the generated wiki pages, with the same section/page hierarchy the web app shows.
- **View Security Analysis / Website Security** reports — findings, severity breakdown, interactive graph, version history — for repos and websites alike.
- **Chat with full parity to the web app**: pick a provider/model from the connected server's configuration, ask questions, toggle Deep Research, toggle 🔐 "Security context" to let the AI see the latest saved scan report. This is the core of the app — everything else is in service of it.
- **Open a `.hdwreader` bundle** — a portable, fully offline export produced by HackDeepWiki's web app (the "Export for HackDeepWikiReader" button, next to the Obsidian export) — for reading a wiki (optionally with its security report) with no server connection at all.

`.zim` archives are always read through a connected HackDeepWiki server (which already has a full `.zim` reader and already supports chatting about `.zim` content) rather than parsed locally — no Flutter/Dart `.zim` library exists, and this keeps chat working uniformly across every content type instead of only for code/website wikis.

## Getting the app

Every push to `main` publishes a rolling pre-release; tagged commits (`vX.Y.Z`) publish a stable release. All three platforms are built automatically by [`.github/workflows/release.yml`](.github/workflows/release.yml) — grab the latest build from the [Releases page](https://github.com/kroryan/HackDeepWikiReader/releases):

- **Linux** → `HackDeepWikiReader-linux-x64.tar.gz` (extract, run `bundle/hackdeepwikireader`)
- **Windows** → `HackDeepWikiReader-windows-x64.zip` (extract, run `hackdeepwikireader.exe`)
- **Android** → `HackDeepWikiReader.apk` (enable "install from unknown sources" if prompted)

## Building from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) plus, per target:

- **Linux desktop**: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`
- **Android**: Android SDK (cmdline-tools, platform-tools, `platforms;android-34`, `build-tools;34.0.0`) and a JDK 17 or 21 (not a bleeding-edge JDK — the Android Gradle Plugin doesn't yet support them)
- **Windows**: Visual Studio with the "Desktop development with C++" workload

```bash
flutter pub get
flutter analyze
flutter test

flutter build linux --release    # build/linux/x64/release/bundle/
flutter build windows --release  # build/windows/x64/runner/Release/
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

## Architecture

```
lib/
  api/            REST client + /ws/chat WebSocket client for a connected
                   HackDeepWiki backend, plus the stream-framing parser
                   (mirrors src/utils/streamParser.ts on the web app).
  bundle/          .hdwreader offline bundle parser (unzip + manifest.json).
  models/          Plain Dart data classes mirroring the backend's Pydantic
                   models / the web app's TypeScript types field-for-field.
  providers/       ChangeNotifier state: the library (saved endpoints +
                   imported bundles), the WikiSource abstraction that lets
                   every screen work identically against a live server or
                   an offline bundle, and per-wiki chat state.
  screens/         One file per screen -- home (library), add/edit
                   endpoint, project list, wiki viewer, security analysis,
                   chat.
  storage/         Local persistence (Hive) -- plain JSON maps, no
                   generated TypeAdapters, so adding a field to any model
                   never needs a codegen step.
  theme/           Ports deepwiki-open's "Cyberpunk Hacker" design tokens
                   (src/app/globals.css) into light/dark Flutter themes.
  widgets/          Shared widgets (page tree, 2D vulnerability graph, ...).
```

To add a new read-only feature: add one method to `lib/api/hackdeepwiki_client.dart` that mirrors an existing `api/api.py` endpoint, consume it from a provider, and build a screen. No existing file needs to change for that. To support a third content source (beyond "live server" and "offline bundle"), implement `WikiSource` (`lib/providers/wiki_source.dart`) -- every screen below the library already only depends on that interface.
