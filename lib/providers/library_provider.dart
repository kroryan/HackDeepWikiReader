import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/hackdeepwiki_client.dart';
import '../models/bundle_entry.dart';
import '../models/endpoint.dart';
import '../storage/local_storage.dart';

/// The "library": saved server endpoints + imported .hdwreader bundles.
/// This is the home-screen state -- add/remove/test endpoints, add/remove
/// bundles. Kept deliberately dumb (no wiki-loading logic) so it stays easy
/// to extend with new library entry types later.
class LibraryProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  List<Endpoint> _endpoints = [];
  List<BundleEntry> _bundles = [];
  final Map<String, bool> _connectionStatus = {}; // endpoint.id -> reachable

  List<Endpoint> get endpoints => List.unmodifiable(_endpoints);
  List<BundleEntry> get bundles => List.unmodifiable(_bundles);
  bool? isReachable(String endpointId) => _connectionStatus[endpointId];

  LibraryProvider() {
    _load();
  }

  void _load() {
    _endpoints = LocalStorage.loadEndpoints();
    _bundles = LocalStorage.loadBundles();
    notifyListeners();
    for (final e in _endpoints) {
      unawaited(checkConnection(e));
    }
  }

  Future<void> checkConnection(Endpoint endpoint) async {
    final ok = await testConnectionFor(endpoint);
    _connectionStatus[endpoint.id] = ok;
    notifyListeners();
  }

  /// One-off connectivity check that doesn't touch saved state -- used by
  /// the "Test connection" button on the add/edit form, against a draft
  /// endpoint that may not be saved (or even valid) yet.
  Future<bool> testConnectionFor(Endpoint endpoint) async {
    final client = HackDeepWikiClient(endpoint);
    try {
      return await client.testConnection();
    } finally {
      client.close();
    }
  }

  Future<Endpoint> addEndpoint(String name, String baseUrl) async {
    final endpoint = Endpoint(id: _uuid.v4(), name: name, baseUrl: baseUrl);
    await LocalStorage.saveEndpoint(endpoint);
    _endpoints = [..._endpoints, endpoint];
    notifyListeners();
    unawaited(checkConnection(endpoint));
    return endpoint;
  }

  Future<void> updateEndpoint(Endpoint endpoint) async {
    await LocalStorage.saveEndpoint(endpoint);
    _endpoints = _endpoints.map((e) => e.id == endpoint.id ? endpoint : e).toList();
    notifyListeners();
    unawaited(checkConnection(endpoint));
  }

  Future<void> removeEndpoint(String id) async {
    await LocalStorage.deleteEndpoint(id);
    _endpoints = _endpoints.where((e) => e.id != id).toList();
    _connectionStatus.remove(id);
    notifyListeners();
  }

  Future<BundleEntry> addBundle(String filePath, String title) async {
    final entry = BundleEntry(
      id: _uuid.v4(),
      filePath: filePath,
      title: title,
      importedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await LocalStorage.saveBundle(entry);
    _bundles = [..._bundles, entry];
    notifyListeners();
    return entry;
  }

  Future<void> removeBundle(String id) async {
    await LocalStorage.deleteBundle(id);
    _bundles = _bundles.where((b) => b.id != id).toList();
    notifyListeners();
  }
}
