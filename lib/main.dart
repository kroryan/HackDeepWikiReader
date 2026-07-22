import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_settings.dart';
import 'navigation.dart';
import 'providers/chat_overlay_controller.dart';
import 'providers/library_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'storage/local_storage.dart';
import 'theme/app_theme.dart';
import 'widgets/chat_overlay_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorage.init();
  runApp(const HackDeepWikiReaderApp());
}

class HackDeepWikiReaderApp extends StatelessWidget {
  const HackDeepWikiReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<SettingsProvider, ChatOverlayController>(
          create: (context) => ChatOverlayController(context.read<SettingsProvider>()),
          update: (context, settings, previous) => previous ?? ChatOverlayController(settings),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          final settings = settingsProvider.settings;
          return MaterialApp(
            navigatorKey: rootNavigatorKey,
            title: 'HackDeepWikiReader',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(AppColors.light, Brightness.light,
                fontFamily: settings.fontFamily, fontScale: settings.fontScale),
            darkTheme: buildAppTheme(AppColors.dark, Brightness.dark,
                fontFamily: settings.fontFamily, fontScale: settings.fontScale),
            themeMode: switch (settings.themeMode) {
              AppThemeMode.system => ThemeMode.system,
              AppThemeMode.light => ThemeMode.light,
              AppThemeMode.dark => ThemeMode.dark,
            },
            // The chat overlay is a sibling of the Navigator, not a
            // descendant -- see ChatOverlayHost's doc comment. That's what
            // lets it stay mounted (and a running chat stay alive) no
            // matter what route is pushed/popped underneath it.
            builder: (context, child) {
              return Stack(
                children: [
                  if (child != null) child,
                  const ChatOverlayHost(),
                ],
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
