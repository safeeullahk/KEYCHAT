import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';

class ApiProfile {
  const ApiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;

  ApiProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? model,
  }) =>
      ApiProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
      };

  factory ApiProfile.fromMap(Map<String, dynamic> map) => ApiProfile(
        id: (map['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: (map['name'] as String?) ?? 'Profile',
        baseUrl: (map['baseUrl'] as String?) ?? SettingsStore.defaultBaseUrl,
        model: (map['model'] as String?) ?? SettingsStore.defaultModel,
      );
}

class AppSettings {
  const AppSettings({
    required this.profiles,
    required this.activeProfileId,
    required this.hasApiKey,
  });

  final List<ApiProfile> profiles;
  final String? activeProfileId;
  final bool hasApiKey;

  ApiProfile get activeProfile {
    if (profiles.isEmpty) {
      return const ApiProfile(
        id: 'default',
        name: 'Default',
        baseUrl: SettingsStore.defaultBaseUrl,
        model: SettingsStore.defaultModel,
      );
    }
    return profiles.firstWhere(
      (p) => p.id == activeProfileId,
      orElse: () => profiles.first,
    );
  }

  String get baseUrl => activeProfile.baseUrl;
  String get model => activeProfile.model;
  bool get isConfigured =>
      hasApiKey && baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  AppSettings copyWith({
    List<ApiProfile>? profiles,
    String? activeProfileId,
    bool clearActiveProfileId = false,
    bool? hasApiKey,
  }) =>
      AppSettings(
        profiles: profiles ?? this.profiles,
        activeProfileId: clearActiveProfileId
            ? null
            : (activeProfileId ?? this.activeProfileId),
        hasApiKey: hasApiKey ?? this.hasApiKey,
      );
}

class SettingsStore {
  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'gpt-4o-mini';

  static const String _baseUrlKey = 'base_url';
  static const String _modelKey = 'model';
  static const String _profilesKey = 'profiles_v1';
  static const String _activeProfileKey = 'active_profile_id';
  static const String _historyKey = 'chat_history_v1';
  static const String _conversationsKey = 'conversations_v1';
  static const String _apiKeyKey = 'api_key';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyBaseUrl = prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
    final legacyModel = prefs.getString(_modelKey) ?? defaultModel;

    List<ApiProfile> profiles = [];
    final rawProfiles = prefs.getString(_profilesKey);
    if (rawProfiles != null && rawProfiles.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProfiles) as List<dynamic>;
        profiles = decoded
            .map((e) => ApiProfile.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        profiles = [];
      }
    }
    if (profiles.isEmpty) {
      profiles = [
        ApiProfile(
          id: 'default',
          name: 'Default',
          baseUrl: legacyBaseUrl,
          model: legacyModel,
        ),
      ];
      await _saveProfiles(prefs, profiles, 'default');
    }

    String? activeId = prefs.getString(_activeProfileKey);
    if (activeId == null || !profiles.any((p) => p.id == activeId)) {
      activeId = profiles.first.id;
      await prefs.setString(_activeProfileKey, activeId);
    }

    String? apiKey;
    try {
      apiKey = await _secure.read(key: _apiKeyKey);
    } catch (_) {
      apiKey = null;
    }

    return AppSettings(
      profiles: profiles,
      activeProfileId: activeId,
      hasApiKey: apiKey != null && apiKey.trim().isNotEmpty,
    );
  }

  Future<void> _saveProfiles(
    SharedPreferences prefs,
    List<ApiProfile> profiles,
    String? activeId,
  ) async {
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((p) => p.toMap()).toList()),
    );
    if (activeId != null) {
      await prefs.setString(_activeProfileKey, activeId);
    }
  }

  Future<String?> readApiKey() async {
    try {
      final value = await _secure.read(key: _apiKeyKey);
      return value != null && value.trim().isNotEmpty ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveApiKey(String apiKey) =>
      _secure.write(key: _apiKeyKey, value: apiKey.trim());

  Future<AppSettings> saveProfiles({
    required List<ApiProfile> profiles,
    required String activeProfileId,
    required bool hasApiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveProfiles(prefs, profiles, activeProfileId);
    final active = profiles.firstWhere(
      (p) => p.id == activeProfileId,
      orElse: () => profiles.first,
    );
    await prefs.setString(_baseUrlKey, active.baseUrl);
    await prefs.setString(_modelKey, active.model);
    return AppSettings(
      profiles: profiles,
      activeProfileId: activeProfileId,
      hasApiKey: hasApiKey,
    );
  }

  Future<AppSettings> saveActiveProfile({
    required String activeProfileId,
    required List<ApiProfile> profiles,
    required bool hasApiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileKey, activeProfileId);
    final active = profiles.firstWhere(
      (p) => p.id == activeProfileId,
      orElse: () => profiles.first,
    );
    await prefs.setString(_baseUrlKey, active.baseUrl);
    await prefs.setString(_modelKey, active.model);
    return AppSettings(
      profiles: profiles,
      activeProfileId: activeProfileId,
      hasApiKey: hasApiKey,
    );
  }

  Future<List<ChatMessage>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => ChatMessage.fromJson(
                Map<String, dynamic>.from(entry),
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveHistory(List<ChatMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode(messages.map((m) => m.toJson()).toList(growable: false)),
      );
    } catch (_) {
      // Best-effort persistence; avoid crashing the chat flow.
    }
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<List<ChatConversation>> loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationsKey);
    if (raw != null) {
      try {
        return (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((e) => ChatConversation.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: true);
      } catch (_) {}
    }
    final legacy = await loadHistory();
    if (legacy.isEmpty) return [];
    final old = ChatConversation(id: DateTime.now().microsecondsSinceEpoch.toString(), title: 'Previous chat', updatedAt: DateTime.now(), messages: legacy);
    await saveConversations([old]);
    return [old];
  }

  Future<void> saveConversations(List<ChatConversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_conversationsKey, jsonEncode(conversations.map((c) => c.toJson()).toList()));
  }
}
