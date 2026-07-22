# HackDeepWikiReader

A read-only companion client for [HackDeepWiki](https://github.com/kroryan/HackDeepWiki), for **Android, Linux, and Windows** from one Flutter codebase.

It never generates wikis and never triggers a security scan — those stay in the main HackDeepWiki app. What it does:

- **Connect to any HackDeepWiki server** by URL (your home server, a work instance, whatever you point it at) and browse every wiki and `.zim` archive cached there.
- **Read** the generated wiki pages, with the same section/page hierarchy the web app shows.
- **View Security Analysis / Website Security** reports — findings, severity breakdown, interactive graph, version history — for repos and websites alike.
- **Chat, fully independent of any HackDeepWiki server**: this app talks directly to your own configured LLM provider (Ollama, ChatGPT/OpenAI, any custom OpenAI-compatible endpoint, or Anthropic Claude — set these up under Settings) and builds its own context from the wiki content already loaded locally, rather than proxying through a backend. Toggle 🔐 "Security context" to fold the latest saved scan report into that context. Chat runs as a floating panel with a maximize toggle on Linux/Windows (mirroring the web app's own chat widget), and full-screen-but-minimizable on Android — the conversation keeps running in the background either way, even after leaving the wiki, until you send it a new message. This is the core of the app — everything else is in service of it.
- **Open a `.hdwreader` bundle** — a portable, fully offline export produced by HackDeepWiki's web app (the "Export for HackDeepWikiReader" button, next to the Obsidian export) — for reading a wiki (optionally with its security report) with no server connection at all.

`.zim` archives are always read through a connected HackDeepWiki server (which already has a full `.zim` reader and already supports chatting about `.zim` content) rather than parsed locally — no Flutter/Dart `.zim` library exists, and this keeps chat working uniformly across every content type instead of only for code/website wikis.

## Getting the app

Every push to `main` publishes a rolling pre-release; tagged commits (`vX.Y.Z`) publish a stable release. All three platforms are built automatically by [`.github/workflows/release.yml`](.github/workflows/release.yml) — grab the latest build from the [Releases page](https://github.com/kroryan/HackDeepWikiReader/releases):

- **Linux** → `HackDeepWikiReader-linux-x64.tar.gz` (extract, run `bundle/hackdeepwikireader`)
- **Windows** → `HackDeepWikiReader-windows-x64.zip` (extract, run `hackdeepwikireader.exe`)
- **Android** → `HackDeepWikiReader.apk` (enable "install from unknown sources" if prompted)
- **Android (Play Store)** → `HackDeepWikiReader.aab`, for uploading to Play Console — not for direct installs

### Android signing

Every CI-built APK/AAB is validly signed, so the APK always installs (and upgrades cleanly release over release) with zero setup: `android/app/ci-installer-key.jks` is a throwaway, intentionally-committed, non-secret key that exists purely so "signed" doesn't depend on secrets nobody configured yet.

To publish to the Play Store you need your own, real upload keystore instead (Play Console requires app updates to keep using the same one forever, so it can't be the throwaway CI key above). Generate one locally:

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

then add these as repo secrets (Settings → Secrets and variables → Actions) — CI picks them up automatically and switches the release signing config over to them:

- `ANDROID_KEYSTORE_BASE64` — `base64 -w0 upload-keystore.jks`
- `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`

(Building locally with your own keystore instead: drop `upload-keystore.jks` into `android/app/` and create `android/key.properties` with `storePassword`/`keyPassword`/`keyAlias`/`storeFile` — both are gitignored.)

## Building from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) plus, per target:

- **Linux desktop**: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`
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

To add a new read-only feature: add one method to `lib/api/hackdeepwiki_client.dart` that mirrors an existing `api/api.py` endpoint, consume it from a provider, and build a screen. No existing file needs to change for that. To support a third content source (beyond "live server" and "offline bundle"), implement `WikiSource` (`lib/providers/wiki_source.dart`) -- every screen below the library already only depends on that interface. To add a fourth LLM provider, implement `LlmClient` (`lib/llm/llm_client.dart`) in its own file and add one case to `buildLlmClient` -- nothing else needs to change.
