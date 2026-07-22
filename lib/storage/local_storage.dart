import 'package:hive_flutter/hive_flutter.dart';

import '../models/bundle_entry.dart';
import '../models/chat_models.dart';
import '../models/endpoint.dart';

/// Local persistence -- saved endpoints, imported bundle library, and
/// per-wiki chat history. Deliberately stores plain JSON maps (no generated
/// Hive TypeAdapters) so adding a field to any model never needs a codegen
/// step; extend a model's toJson/fromJson and it just works.
class LocalStorage {
  static const _endpointsBox = 'endpoints';
  static const _bundlesBox = 'bundles';
  static const _chatSessionsBox = 'chat_sessions';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<Map>(_endpointsBox),
      Hive.openBox<Map>(_bundlesBox),
      Hive.openBox<Map>(_chatSessionsBox),
    ]);
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
}
