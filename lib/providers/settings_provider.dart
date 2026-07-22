import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/llm_config.dart';
import '../storage/local_storage.dart';

/// App-wide settings: appearance (font family/size, theme mode) and this
/// app's own LLM provider connections. Everything here is independent of
/// any connected HackDeepWiki server -- see lib/llm/ for the clients these
/// connections drive.
class SettingsProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  AppSettings _settings = LocalStorage.loadSettings();
  List<LlmConnection> _connections = LocalStorage.loadLlmConnections();

  AppSettings get settings => _settings;
  List<LlmConnection> get connections => List.unmodifiable(_connections);
  bool get hasAnyConnection => _connections.isNotEmpty;

  LlmConnection? get defaultConnection {
    if (_connections.isEmpty) return null;
    final id = _settings.defaultConnectionId;
    if (id != null) {
      for (final c in _connections) {
        if (c.id == id) return c;
      }
    }
    return _connections.first;
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await LocalStorage.saveSettings(settings);
    notifyListeners();
  }

  Future<LlmConnection> addConnection({
    required String name,
    required LlmPreset preset,
    required String baseUrl,
    String? apiKey,
    required String model,
  }) async {
    final connection = LlmConnection(
      id: _uuid.v4(),
      name: name,
      kind: preset.kind,
      preset: preset,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      isDefault: _connections.isEmpty,
    );
    await LocalStorage.saveLlmConnection(connection);
    _connections = [..._connections, connection];
    if (_connections.length == 1) {
      await updateSettings(_settings.copyWith(defaultConnectionId: connection.id));
      return connection;
    }
    notifyListeners();
    return connection;
  }

  Future<void> updateConnection(LlmConnection connection) async {
    await LocalStorage.saveLlmConnection(connection);
    _connections = _connections.map((c) => c.id == connection.id ? connection : c).toList();
    notifyListeners();
  }

  Future<void> removeConnection(String id) async {
    await LocalStorage.deleteLlmConnection(id);
    _connections = _connections.where((c) => c.id != id).toList();
    if (_settings.defaultConnectionId == id) {
      await updateSettings(
        _settings.copyWith(defaultConnectionId: _connections.isNotEmpty ? _connections.first.id : null),
      );
    }
    notifyListeners();
  }

  Future<void> setDefaultConnection(String id) async {
    await updateSettings(_settings.copyWith(defaultConnectionId: id));
  }
}
