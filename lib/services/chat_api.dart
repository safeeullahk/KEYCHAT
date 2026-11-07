import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';

class ChatApiException implements Exception {
  ChatApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Trims whitespace and trailing slashes so `$base/chat/completions` is well
/// formed whether the user typed `https://api.openai.com/v1/` or without it.
String normalizeBaseUrl(String raw) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// Turns an OpenAI-style error body (or a bare status) into something a person
/// can act on.
String apiErrorMessage(int status, String body) {
  String? detail;
  if (body.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message'] ?? error['code'];
          if (message != null) detail = message.toString();
        } else if (error is String) {
          detail = error;
        } else if (decoded['message'] is String) {
          detail = decoded['message'] as String;
        }
      }
    } catch (_) {
      detail = body.trim();
    }
  }
  final suffix =
      detail == null || detail.trim().isEmpty ? '' : ' ${detail.trim()}';
  switch (status) {
    case 400:
      return 'The request was rejected (400).$suffix';
    case 401:
      return 'The API key was rejected (401). Check it in Settings.'
          '$suffix';
    case 402:
      return 'This key is out of credit or needs billing set up (402).$suffix';
    case 403:
      return 'This key is not allowed to use that model (403).$suffix';
    case 404:
      return 'That model or endpoint was not found (404). Check the model name '
          'in Settings.$suffix';
    case 429:
      return 'Rate limit or quota reached (429). Wait a moment and try again.'
          '$suffix';
    case 500:
    case 502:
    case 503:
    case 504:
      return 'The provider is having trouble ($status). Try again shortly.'
          '$suffix';
    default:
      return 'The API returned an unexpected error ($status).$suffix';
  }
}

class ChatApi {
  ChatApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 120);

  /// Streams reply text as it arrives. Providers that ignore `stream: true` and
  /// return one JSON body are handled too.
  Stream<String> streamReply({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
  }) async* {
    final uri = Uri.parse('${normalizeBaseUrl(baseUrl)}/chat/completions');
    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer $apiKey',
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'messages': messages.map((message) => message.toApiJson()).toList(),
      });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_timeout);
    } on TimeoutException {
      throw ChatApiException('The API took too long to respond.');
    } on Exception catch (error) {
      throw ChatApiException(
        'Could not reach the API at ${normalizeBaseUrl(baseUrl)}. '
        'Check the base URL, your key and your connection. ($error)',
      );
    }

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      throw ChatApiException(apiErrorMessage(response.statusCode, body));
    }

    final lines =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());

    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
      if (trimmed.startsWith('data:')) {
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') break;
        final text = _textFromPayload(data);
        if (text != null && text.isNotEmpty) yield text;
        continue;
      }
      // A provider that ignored streaming sends one JSON object instead.
      if (trimmed.startsWith('{')) {
        final text = _textFromPayload(trimmed);
        if (text != null && text.isNotEmpty) yield text;
      }
    }
  }

  Future<List<String>> listModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final uri = Uri.parse('${normalizeBaseUrl(baseUrl)}/models');
    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(_timeout);
    } on TimeoutException {
      throw ChatApiException('The API took too long to list its models.');
    } on Exception catch (error) {
      throw ChatApiException(
        'Could not reach ${normalizeBaseUrl(baseUrl)}. ($error)',
      );
    }

    if (response.statusCode >= 400) {
      throw ChatApiException(
        apiErrorMessage(response.statusCode, response.body),
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw ChatApiException('That endpoint did not return a model list.');
    }
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) return const [];
    final ids = data
        .whereType<Map>()
        .map((model) => model['id'])
        .whereType<String>()
        .toList()
      ..sort();
    return ids;
  }

  String? _textFromPayload(String payload) {
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final choice = choices.first;
    if (choice is! Map) return null;

    final delta = choice['delta'];
    if (delta is Map) {
      final content = delta['content'] ?? delta['reasoning_content'];
      if (content is String) return content;
      if (content is List) {
        return content
            .whereType<Map>()
            .map((part) => part['text'])
            .whereType<String>()
            .join();
      }
    }
    final message = choice['message'];
    if (message is Map && message['content'] is String) {
      return message['content'] as String;
    }
    return null;
  }
}
