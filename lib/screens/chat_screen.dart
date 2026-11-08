import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:mime/mime.dart';

import '../models/chat_message.dart';
import '../services/settings_store.dart';
import '../viewmodels/chat_view_model.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.store,
    required this.initialSettings,
  });

  final SettingsStore store;
  final AppSettings initialSettings;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatViewModel _vm;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  late AppSettings _settings;
  List<ChatMessage> get _messages => _vm.messages;
  List<ChatConversation> get _conversations => _vm.conversations;
  List<ChatAttachment> get _pendingAttachments => _vm.pendingAttachments;
  bool get _sending => _vm.sending;
  String? get _error => _vm.error;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _vm = ChatViewModel(store: widget.store, settings: _settings)..addListener(_onViewModelChanged);
    _restoreHistory();
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _vm.dispose();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    setState(() => _settings = _vm.settings);
  }

  Future<void> _restoreHistory() async {
    try {
      await _vm.restore();
      _scrollToEnd(jump: true);
    } catch (_) {
      // Keep a usable empty chat if history can't be restored.
    }
  }

  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (_) =>
            SettingsScreen(store: widget.store, initial: _settings),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _settings = updated);
    _vm.updateSettings(updated);
  }

  Future<void> _switchProfile(ApiProfile profile) async => _vm.switchProfile(profile);

  Future<void> _pickAttachments() async {
    if (_sending) return;
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty || !mounted) return;
      final next = <ChatAttachment>[];
      for (final file in files) {
        final name = file.name;
        List<int> bytes;
        try {
          bytes = await file.readAsBytes();
        } catch (_) {
          final path = file.path;
          if (path != null) {
            try {
              bytes = await File(path).readAsBytes();
            } catch (_) {
              continue;
            }
          } else {
            continue;
          }
        }
        final mime = lookupMimeType(name, headerBytes: bytes.take(16).toList()) ??
            'application/octet-stream';
        const maxBytes = 4 * 1024 * 1024; // 4MB
        if (bytes.length > maxBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$name is too large (max 4 MB).')),
            );
          }
          continue;
        }
        if (mime.startsWith('image/')) {
          final b64 = base64Encode(bytes);
          next.add(ChatAttachment(
            name: name,
            mimeType: mime,
            dataUrl: 'data:$mime;base64,$b64',
          ));
        } else {
          // Try to read as text; fall back to a binary notice.
          String? text;
          try {
            text = utf8.decode(bytes);
          } catch (_) {
            try {
              text = latin1.decode(bytes);
            } catch (_) {
              text = null;
            }
          }
          next.add(ChatAttachment(
            name: name,
            mimeType: mime,
            textContent: text,
          ));
        }
      }
      if (next.isNotEmpty && mounted) {
        _vm.addAttachments(next);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick files: $e')),
        );
      }
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;

    if (!_settings.isConfigured) {
      await _openSettings();
      return;
    }

    _input.clear();
    _scrollToEnd();
    await _vm.send(text);
    _scrollToEnd();
  }

  Future<void> _stop() async => _vm.stop();

  Future<void> _confirmNewChat() async {
    if (_messages.isEmpty && _pendingAttachments.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new chat?'),
        content: const Text('This clears the conversation on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('New chat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _vm.startNewChat();
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = _settings.activeProfile;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Column(
          children: [
            Text(active.name, overflow: TextOverflow.ellipsis),
            Text(
              _settings.isConfigured ? active.model : 'No API key configured',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Profiles & history',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed:
                (_messages.isEmpty && _pendingAttachments.isEmpty) ? null : _confirmNewChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _AppDrawer(
        settings: _settings,
        messages: _messages,
        conversations: _conversations,
        onOpenConversation: (conversation) {
          _vm.openConversation(conversation);
          _scrollToEnd(jump: true);
        },
        onSwitch: _switchProfile,
        onNewChat: _confirmNewChat,
        onOpenSettings: () async {
          Navigator.of(context).pop();
          await _openSettings();
        },
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                if (!_settings.isConfigured)
                  _SetupBanner(onAddKey: _openSettings),
                if (_error != null)
                  _ErrorBanner(
                    message: _error!,
                    onDismiss: () => _vm.dismissError(),
                  ),
                Expanded(
                  child: _messages.isEmpty
                      ? _EmptyState(
                          configured: _settings.isConfigured,
                          model: active.model,
                          onAddKey: _openSettings,
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final pending = _sending &&
                                index == _messages.length - 1 &&
                                message.role == ChatRole.assistant &&
                                message.text.isEmpty;
                            return _MessageBubble(
                              message: message,
                              pending: pending,
                            );
                          },
                        ),
                ),
                _buildComposer(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingAttachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (int i = 0; i < _pendingAttachments.length; i++)
                      InputChip(
                        avatar: Icon(
                          _pendingAttachments[i].isImage
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _pendingAttachments[i].name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: _sending
                            ? null
                            : () => setState(() {
                                  _vm.removeAttachment(i);
                                }),
                      ),
                  ],
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Attach files or images',
                onPressed: _sending ? null : _pickAttachments,
                icon: const Icon(Icons.attach_file_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  enabled: !_sending,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _settings.isConfigured
                        ? 'Message ${_settings.model}'
                        : 'Add an API key to start',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _sending
                  ? IconButton.filledTonal(
                      tooltip: 'Stop',
                      onPressed: _stop,
                      icon: const Icon(Icons.stop_rounded),
                    )
                  : IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _send,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.settings,
    required this.messages,
    required this.conversations,
    required this.onOpenConversation,
    required this.onSwitch,
    required this.onNewChat,
    required this.onOpenSettings,
  });

  final AppSettings settings;
  final List<ChatMessage> messages;
  final List<ChatConversation> conversations;
  final ValueChanged<ChatConversation> onOpenConversation;
  final ValueChanged<ApiProfile> onSwitch;
  final VoidCallback onNewChat;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview =
        messages.isNotEmpty ? messages.last.text : 'No messages yet';
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Text(
                'KeyChat',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onNewChat,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New chat'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Models & API keys'),
            ),
            const SizedBox(height: 18),
            Text('Current chat', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Card(
              elevation: 0,
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              child: ListTile(
                title: const Text('This conversation'),
                subtitle: Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                leading: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            Text('Chat history', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final conversation in conversations)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${conversation.messages.length} messages'),
                onTap: () {
                  Navigator.of(context).pop();
                  onOpenConversation(conversation);
                },
              ),
            const SizedBox(height: 14),
            Text('Model profiles', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final profile in settings.profiles)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                selected: profile.id == settings.activeProfile.id,
                selectedTileColor:
                    scheme.secondaryContainer.withValues(alpha: 0.55),
                leading: Icon(
                  profile.id == settings.activeProfile.id
                      ? Icons.check_circle_rounded
                      : Icons.smart_toy_outlined,
                ),
                title: Text(profile.name),
                subtitle: Text(
                  profile.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onSwitch(profile);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.pending = false});

  final ChatMessage message;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 20),
          ),
        ),
        child: pending
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: message.attachments
                            .map(
                              (a) => Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(
                                  a.isImage
                                      ? Icons.image_outlined
                                      : Icons.insert_drive_file_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  a.name,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  isUser
                      ? SelectableText(
                          message.text.isEmpty
                              ? '(attachments)'
                              : message.text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onPrimary,
                            height: 1.45,
                          ),
                        )
                      : _AssistantMarkdown(text: message.text),
                ],
              ),
      ),
    );
  }
}

class _AssistantMarkdown extends StatelessWidget {
  const _AssistantMarkdown({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final codeBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F8);
    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurface,
      height: 1.45,
    );
    return MarkdownBody(
      data: text.isEmpty ? ' ' : text,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: baseStyle,
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A),
          backgroundColor: codeBg,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableScrollbarThumbVisibility: true,
        blockquoteDecoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: scheme.primary, width: 3),
          ),
        ),
      ),
      builders: {'pre': _CopyableCodeBlockBuilder(codeBg: codeBg, foreground: isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A), border: scheme.outlineVariant.withValues(alpha: 0.35))},
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
  }
}

class _CopyableCodeBlockBuilder extends MarkdownElementBuilder {
  _CopyableCodeBlockBuilder({required this.codeBg, required this.foreground, required this.border});
  final Color codeBg;
  final Color foreground;
  final Color border;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    final code = text.text;
    return Builder(builder: (context) => Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
          },
          icon: const Icon(Icons.copy_rounded, size: 16), label: const Text('Copy'),
        )),
        SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: SelectableText(code, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: foreground))),
      ]),
    ));
  }
}



class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.configured,
    required this.model,
    required this.onAddKey,
  });

  final bool configured;
  final String model;
  final VoidCallback onAddKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 34,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              configured ? 'What can I help with?' : 'Add your API key',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              configured
                  ? 'Chatting with $model. Attach files/images with the paperclip, and code replies are easy to copy.'
                  : 'Paste any compatible API key once. Add multiple model/API profiles and attach files in chat.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            if (!configured) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAddKey,
                icon: const Icon(Icons.key_rounded),
                label: const Text('Add API key'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.onAddKey});

  final VoidCallback onAddKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.key_rounded, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No API key yet. Add one to start chatting.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(onPressed: onAddKey, child: const Text('Add key')),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}
