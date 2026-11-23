import 'dart:async';
import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:http/http.dart' as http;

import 'a2ui_transport.dart';

/// HTTP JSONL + SSE implementation of [A2uiTransport].
class HttpJsonlTransport implements A2uiTransport {
  HttpJsonlTransport({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  bool _disposed = false;

  Uri _uri(String path) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed$path');
  }

  @override
  Stream<Map<String, Object?>> start({String? previousSurfaceId}) {
    return _postJsonl(
      '/a2ui/start',
      {
        if (previousSurfaceId != null) 'surfaceId': previousSurfaceId,
      },
    );
  }

  @override
  Stream<Map<String, Object?>> sendAction({
    required A2uiRendererAction action,
    required Map<String, Object?>? rendererDataModel,
  }) {
    return _postJsonl(
      '/a2ui/action',
      {
        'version': A2uiProtocolVersion.v1_0.jsonValue,
        'action': action.toJson(),
        'metadata': {
          if (rendererDataModel != null)
            'a2uiRendererDataModel': rendererDataModel,
        },
      },
    );
  }

  @override
  Stream<Map<String, Object?>> refresh({
    required String? surfaceId,
    required String? stepId,
    required Map<String, Object?>? rendererDataModel,
  }) {
    return _postJsonl(
      '/a2ui/refresh',
      {
        if (surfaceId != null) 'surfaceId': surfaceId,
        if (stepId != null) 'stepId': stepId,
        'metadata': {
          if (rendererDataModel != null)
            'a2uiRendererDataModel': rendererDataModel,
        },
      },
    );
  }

  Stream<Map<String, Object?>> _postJsonl(
    String path,
    Map<String, Object?> payload,
  ) async* {
    final http.StreamedResponse response;
    try {
      final request = http.Request('POST', _uri(path))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'application/jsonl'
        ..body = jsonEncode(payload);
      response = await _client.send(request);
    } catch (e) {
      throw NetworkTransportFailure(
        'Sunucuya bağlanılamadı ($baseUrl). Server çalışıyor mu?',
        cause: e,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Sunucu hatası (HTTP ${response.statusCode})';
      String? code;
      try {
        final errBody = await response.stream.bytesToString();
        final decoded = jsonDecode(errBody);
        if (decoded is Map) {
          message = (decoded['message'] as String?) ?? message;
          code = decoded['code'] as String?;
        }
      } catch (_) {}
      throw StatusTransportFailure(
        statusCode: response.statusCode,
        message: message,
        code: code,
      );
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final rawLine in lines) {
        final trimmed = rawLine.trim();
        if (trimmed.isEmpty) continue;
        final Object? decoded;
        try {
          decoded = jsonDecode(trimmed);
        } catch (e) {
          throw MalformedTransportFailure(
            'Geçersiz JSONL satırı alındı: $e',
            rawLine: trimmed,
          );
        }
        if (decoded is! Map) {
          throw MalformedTransportFailure(
            'A2UI zarfı JSON nesnesi olmalıdır.',
            rawLine: trimmed,
          );
        }
        yield decoded.cast<String, Object?>();
      }
    } on TransportFailure {
      rethrow;
    } catch (e) {
      throw NetworkTransportFailure(
        'Akış okunurken bağlantı kesildi: $e',
        cause: e,
      );
    }
  }

  @override
  Stream<PublishedEvent> events() async* {
    while (!_disposed) {
      http.Client? sseClient;
      try {
        sseClient = http.Client();
        final request = http.Request('GET', _uri('/events'))
          ..headers['Accept'] = 'text/event-stream'
          ..headers['Cache-Control'] = 'no-cache';

        final response = await sseClient.send(request);
        if (response.statusCode == 200) {
          String? currentEvent;
          final dataBuffer = StringBuffer();

          await for (final line in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (_disposed) break;

            if (line.isEmpty) {
              if (currentEvent == 'published' && dataBuffer.isNotEmpty) {
                try {
                  final json =
                      jsonDecode(dataBuffer.toString()) as Map<String, dynamic>;
                  final version = (json['version'] as num?)?.toInt();
                  if (version != null) {
                    yield PublishedEvent(version: version);
                  }
                } catch (_) {}
              }
              currentEvent = null;
              dataBuffer.clear();
              continue;
            }

            if (line.startsWith(':')) {
              continue; // SSE comment / keepalive
            }
            if (line.startsWith('event:')) {
              currentEvent = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              dataBuffer.write(line.substring(5).trim());
            }
          }
        }
      } catch (_) {
        // Reconnect after brief backoff if SSE drops
      } finally {
        sseClient?.close();
      }

      if (!_disposed) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
  }
}

