import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../services/chat_api.dart';
import '../services/settings_store.dart';

/// Owns chat state and coordinates persistence and API calls for ChatScreen.
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({required SettingsStore store, required AppSettings settings})
      : _store = store,
        _settings = settings;

  final SettingsStore _store;
  final ChatApi _api = ChatApi();
  AppSettings _settings;
  List<ChatMessage> messages = const [];
  List<ChatConversation> conversations = [];
  List<ChatAttachment> pendingAttachments = const [];
  String? error;
  bool sending = false;
  String? _currentConversationId;
  StreamSubscription<String>? _subscription;
  AppSettings get settings => _settings;

  Future<void> restore() async {
    conversations = await _store.loadConversations();
    if (conversations.isNotEmpty) {
      _currentConversationId = conversations.first.id;
      messages = conversations.first.messages;
    }
    notifyListeners();
  }

  void updateSettings(AppSettings settings) => _settings = settings;
  void dismissError() { error = null; notifyListeners(); }
  void addAttachments(List<ChatAttachment> items) {
    pendingAttachments = [...pendingAttachments, ...items];
    notifyListeners();
  }
  void removeAttachment(int index) {
    pendingAttachments = [...pendingAttachments]..removeAt(index);
    notifyListeners();
  }

  Future<void> send(String text) async {
    if (sending) return;
    final apiKey = await _store.readApiKey();
    if (apiKey == null) {
      error = 'No API key configured.';
      notifyListeners();
      return;
    }
    final history = [...messages, ChatMessage(role: ChatRole.user, text: text, attachments: pendingAttachments)];
    sending = true;
    error = null;
    pendingAttachments = const [];
    messages = [...history, const ChatMessage(role: ChatRole.assistant, text: '')];
    notifyListeners();
    await _persist(history);
    final buffer = StringBuffer();
    _subscription = _api.streamReply(baseUrl: _settings.baseUrl, apiKey: apiKey, model: _settings.model, messages: history).listen(
      (chunk) { buffer.write(chunk); messages = [...messages.take(messages.length - 1), ChatMessage(role: ChatRole.assistant, text: buffer.toString())]; notifyListeners(); },
      onError: (Object e) => _finish(error: e is ChatApiException ? e.message : e.toString()),
      onDone: _finish,
    );
  }

  Future<void> stop() async { final sub = _subscription; _subscription = null; await sub?.cancel(); _finish(); }
  void _finish({String? error}) {
    _subscription = null;
    final result = [...messages];
    if (result.isNotEmpty && result.last.role == ChatRole.assistant && result.last.text.trim().isEmpty) result.removeLast();
    messages = result;
    sending = false;
    this.error = error;
    notifyListeners();
    _persist(result);
  }

  Future<void> _persist(List<ChatMessage> value) async {
    if (value.isEmpty) return;
    final id = _currentConversationId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final first = value.firstWhere((m) => m.role == ChatRole.user, orElse: () => value.first).text.trim();
    final title = first.isEmpty ? 'New chat' : first.split('\n').first;
    final item = ChatConversation(id: id, title: title.length > 48 ? '${title.substring(0, 48)}…' : title, updatedAt: DateTime.now(), messages: List.unmodifiable(value));
    _currentConversationId = id;
    conversations = [item, ...conversations.where((c) => c.id != id)];
    await _store.saveConversations(conversations);
    notifyListeners();
  }

  Future<void> startNewChat() async {
    await _persist(messages);
    messages = const [];
    _currentConversationId = null;
    pendingAttachments = const [];
    error = null;
    notifyListeners();
  }

  void openConversation(ChatConversation item) {
    _currentConversationId = item.id;
    messages = item.messages;
    error = null;
    notifyListeners();
  }

  Future<void> switchProfile(ApiProfile profile) async {
    _settings = await _store.saveActiveProfile(activeProfileId: profile.id, profiles: _settings.profiles, hasApiKey: _settings.hasApiKey);
    notifyListeners();
  }

  @override
  void dispose() { _subscription?.cancel(); super.dispose(); }
}
