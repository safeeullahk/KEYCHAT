import 'package:flutter_test/flutter_test.dart';
import 'package:keychat/models/chat_message.dart';
import 'package:keychat/services/chat_api.dart';

void main() {
  group('ChatMessage', () {
    test('round-trips through stored JSON', () {
      const message = ChatMessage(
        role: ChatRole.assistant,
        text: 'Hello there',
      );
      final restored = ChatMessage.fromJson(message.toJson());
      expect(restored.role, ChatRole.assistant);
      expect(restored.text, 'Hello there');
    });

    test('serialises for the chat completions API', () {
      const message = ChatMessage(role: ChatRole.user, text: 'Hi');
      expect(message.toApiJson(), {'role': 'user', 'content': 'Hi'});
    });

    test('falls back to the user role for unknown stored values', () {
      expect(
        ChatMessage.fromJson({'role': 'system', 'text': 'x'}).role,
        ChatRole.user,
      );
    });
  });

  group('normalizeBaseUrl', () {
    test('strips whitespace and trailing slashes', () {
      expect(normalizeBaseUrl(' https://api.openai.com/v1/ '),
          'https://api.openai.com/v1');
      expect(normalizeBaseUrl('https://api.openai.com/v1///'),
          'https://api.openai.com/v1');
    });
  });

  group('apiErrorMessage', () {
    test('surfaces the provider message', () {
      final message =
          apiErrorMessage(401, '{"error":{"message":"Incorrect API key"}}');
      expect(message, contains('Incorrect API key'));
      expect(message, contains('401'));
    });

    test('explains a bad key without a body', () {
      expect(apiErrorMessage(401, ''), contains('API key'));
    });

    test('handles unknown statuses', () {
      expect(apiErrorMessage(418, ''), contains('418'));
    });
  });
}
