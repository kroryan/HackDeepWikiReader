import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:hackdeepwikireader/main.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hdwr_test');
    Hive.init(tempDir.path);
    await Future.wait([
      Hive.openBox<Map>('endpoints'),
      Hive.openBox<Map>('bundles'),
      Hive.openBox<Map>('chat_sessions'),
      Hive.openBox<Map>('llm_connections'),
      Hive.openBox<Map>('settings'),
    ]);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('App launches and shows the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const HackDeepWikiReaderApp());
    await tester.pumpAndSettle();

    expect(find.text('HackDeepWikiReader'), findsOneWidget);
    expect(find.text('Servers'), findsOneWidget);
    expect(find.text('Offline bundles'), findsOneWidget);
  });
}
