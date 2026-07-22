import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/library_provider.dart';
import 'screens/home_screen.dart';
import 'storage/local_storage.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorage.init();
  runApp(const HackDeepWikiReaderApp());
}

class HackDeepWikiReaderApp extends StatelessWidget {
  const HackDeepWikiReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LibraryProvider(),
      child: MaterialApp(
        title: 'HackDeepWikiReader',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(AppColors.light, Brightness.light),
        darkTheme: buildAppTheme(AppColors.dark, Brightness.dark),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
