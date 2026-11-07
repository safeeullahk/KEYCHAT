enum ChatRole {
  user('user'),
  assistant('assistant');

  const ChatRole(this.wireName);

  final String wireName;

  static ChatRole fromName(String? name) =>
      name == 'assistant' ? ChatRole.assistant : ChatRole.user;
}

class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.mimeType,
    this.textContent,
    this.dataUrl,
  });

  final String name;
  final String mimeType;
  final String? textContent; // for text-like files
  final String? dataUrl; // data:mime;base64,... for images/small binary

  bool get isImage => mimeType.startsWith('image/');

  /// Persisted to local history. Large image data URLs are omitted to keep
  /// storage small and reliable; text content is kept (trimmed).
  Map<String, dynamic> toJson() => {
        'name': name,
        'mimeType': mimeType,
        if (textContent != null && textContent!.isNotEmpty)
          'textContent': textContent!.length > 12000
              ? '${textContent!.substring(0, 12000)}\n...[truncated]'
              : textContent,
        // dataUrl intentionally not persisted
      };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        name: (json['name'] as String?) ?? 'file',
        mimeType: (json['mimeType'] as String?) ?? 'application/octet-stream',
        textContent: json['textContent'] as String?,
        dataUrl: json['dataUrl'] as String?,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.attachments = const [],
  });

  final ChatRole role;
  final String text;
  final List<ChatAttachment> attachments;

  Map<String, dynamic> toJson() => {
        'role': role.wireName,
        'text': text,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  /// OpenAI-compatible chat completions payload. Uses multimodal `content`
  /// array when the user message has attachments.
  dynamic toApiContent() {
    if (role != ChatRole.user || attachments.isEmpty) return text;

    final parts = <Map<String, dynamic>>[];
    final textParts = <String>[];
    if (text.trim().isNotEmpty) textParts.add(text.trim());
    for (final a in attachments) {
      if (a.textContent != null && a.textContent!.trim().isNotEmpty) {
        textParts.add('--- Attached file: ${a.name} ---\n${a.textContent}');
      } else if (a.isImage && a.dataUrl != null) {
        // image handled below as image_url part
      } else {
        textParts.add('[Attached file: ${a.name} (${a.mimeType})]');
      }
    }
    final combined = textParts.join('\n\n');
    parts.add({'type': 'text', 'text': combined.isEmpty ? ' ' : combined});

    for (final a in attachments) {
      if (a.isImage && a.dataUrl != null) {
        parts.add({
          'type': 'image_url',
          'image_url': {'url': a.dataUrl},
        });
      }
    }
    return parts;
  }

  Map<String, dynamic> toApiJson() => {
        'role': role.wireName,
        'content': toApiContent(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: ChatRole.fromName(json['role'] as String?),
        text: json['text'] as String? ?? '',
        attachments: (json['attachments'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => ChatAttachment.fromJson(
                    Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );
}
