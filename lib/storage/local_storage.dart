import 'dart:io';

import 'package:hive/hive.dart';

import '../models/app_settings.dart';
import '../models/bundle_entry.dart';
import '../models/chat_models.dart';
import '../models/endpoint.dart';
import '../models/llm_config.dart';
import '../models/zim_entry.dart';
import 'app_directories.dart';

/// Local persistence -- saved endpoints, imported bundle library, per-wiki
/// chat history, the app's own LLM connections, and app settings.
/// Deliberately stores plain JSON maps (no generated Hive TypeAdapters) so
/// adding a field to any model never needs a codegen step; extend a model's
/// toJson/fromJson and it just works.
class LocalStorage {
  static const _endpointsBox = 'endpoints';
  static const _bundlesBox = 'bundles';
  static const _zimsBox = 'zims';
  static const _chatSessionsBox = 'chat_sessions';
  static const _llmConnectionsBox = 'llm_connections';
  static const _settingsBox = 'settings';
  static const _settingsKey = 'app_settings';

  static Future<void> init() async {
    Hive.init(AppDirectories.data.path);
    await Future.wait([
      Hive.openBox<Map>(_endpointsBox),
      Hive.openBox<Map>(_bundlesBox),
      Hive.openBox<Map>(_zimsBox),
      Hive.openBox<Map>(_chatSessionsBox),
      Hive.openBox<Map>(_llmConnectionsBox),
      Hive.openBox<Map>(_settingsBox),
    ]);
    await _migrateZimPaths();
  }

  static Future<void> _migrateZimPaths() async {
    final box = Hive.box<Map>(_zimsBox);
    for (final key in box.keys.toList(growable: false)) {
      final raw = box.get(key);
      if (raw == null) continue;
      final entry = ZimEntry.fromJson(Map<String, dynamic>.from(raw));
      final migratedPath = AppDirectories.migratedZimPath(entry.filePath);
      if (migratedPath == entry.filePath || !File(migratedPath).existsSync()) {
        continue;
      }
      await box.put(
        key,
        ZimEntry(
          id: entry.id,
          filePath: migratedPath,
          title: entry.title,
          importedAt: entry.importedAt,
        ).toJson(),
      );
    }
  }

  // --- Endpoints ---

  static List<Endpoint> loadEndpoints() {
    final box = Hive.box<Map>(_endpointsBox);
    return box.values.map((m) => Endpoint.fromJson(Map<String, dynamic>.from(m))).toList();
  }

  static Future<void> saveEndpoint(Endpoint endpoint) async {
    final box = Hive.box<Map>(_endpointsBox);
    await box.put(endpoint.id, endpoint.toJson());
  }

  static Future<void> deleteEndpoint(String id) async {
    await Hive.box<Map>(_endpointsBox).delete(id);
  }

  // --- Bundles ---

  static List<BundleEntry> loadBundles() {
    final box = Hive.box<Map>(_bundlesBox);
    return box.values.map((m) => BundleEntry.fromJson(Map<String, dynamic>.from(m))).toList();
  }

  static Future<void> saveBundle(BundleEntry bundle) async {
    final box = Hive.box<Map>(_bundlesBox);
    await box.put(bundle.id, bundle.toJson());
  }

  static Future<void> deleteBundle(String id) async {
    await Hive.box<Map>(_bundlesBox).delete(id);
  }

  // --- .zim archives (imported directly, read fully offline) ---

  static List<ZimEntry> loadZims() {
    final box = Hive.box<Map>(_zimsBox);
    return box.values.map((m) => ZimEntry.fromJson(Map<String, dynamic>.from(m))).toList();
  }

  static Future<void> saveZim(ZimEntry zim) async {
    final box = Hive.box<Map>(_zimsBox);
    await box.put(zim.id, zim.toJson());
  }

  static Future<void> deleteZim(String id) async {
    await Hive.box<Map>(_zimsBox).delete(id);
  }

  // --- Chat sessions (keyed by "<sourceId>::<sessionId>" so sessions from
  // different wikis/endpoints never collide) ---

  static List<ChatSession> loadChatSessions(String sourceId) {
    final box = Hive.box<Map>(_chatSessionsBox);
    return box.keys
        .where((k) => (k as String).startsWith('$sourceId::'))
        .map((k) => ChatSession.fromJson(Map<String, dynamic>.from(box.get(k)!)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<void> saveChatSession(String sourceId, ChatSession session) async {
    final box = Hive.box<Map>(_chatSessionsBox);
    await box.put('$sourceId::${session.id}', session.toJson());
  }

  static Future<void> deleteChatSession(String sourceId, String sessionId) async {
    await Hive.box<Map>(_chatSessionsBox).delete('$sourceId::$sessionId');
  }

  // --- LLM connections (this app's own provider config, independent of
  // any connected HackDeepWiki server) ---

  static List<LlmConnection> loadLlmConnections() {
    final box = Hive.box<Map>(_llmConnectionsBox);
    return box.values.map((m) => LlmConnection.fromJson(Map<String, dynamic>.from(m))).toList();
  }

  static Future<void> saveLlmConnection(LlmConnection connection) async {
    final box = Hive.box<Map>(_llmConnectionsBox);
    await box.put(connection.id, connection.toJson());
  }

  static Future<void> deleteLlmConnection(String id) async {
    await Hive.box<Map>(_llmConnectionsBox).delete(id);
  }

  // --- App settings (single record) ---

  static AppSettings loadSettings() {
    final box = Hive.box<Map>(_settingsBox);
    final raw = box.get(_settingsKey);
    if (raw == null) return const AppSettings();
    return AppSettings.fromJson(Map<String, dynamic>.from(raw));
  }

  static Future<void> saveSettings(AppSettings settings) async {
    await Hive.box<Map>(_settingsBox).put(_settingsKey, settings.toJson());
  }
}
