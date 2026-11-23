import 'dart:convert';

import 'package:flow_core/flow_core.dart';
import 'package:http/http.dart' as http;

import '../sessions/submission_models.dart';

/// Response from `/flow/ai-edit`.
class StudioAiEditResponse {
  const StudioAiEditResponse({
    required this.snapshot,
    required this.summary,
    required this.usedRemoteLlm,
  });

  final FlowSnapshot snapshot;
  final String summary;
  final bool usedRemoteLlm;
}

/// Abstract API client for Studio to communicate with the A2UI Flow Server.
abstract class StudioApiClient {
  Future<FlowSnapshot> getFlow();
  Future<FlowSnapshot> saveDraft(FlowDefinition draft);
  Future<FlowSnapshot> publish();
  Future<FlowSnapshot> reset();
  Future<List<Map<String, Object?>>> previewStep(String? stepId);
  Future<StudioAiEditResponse> aiEdit(String prompt);

  /// Player sessions and what they submitted (`GET /sessions`).
  Future<List<StudioSession>> getSessions();

  /// Clears the submission log (`DELETE /sessions`).
  Future<void> clearSessions();

  void dispose();
}

/// HTTP implementation of [StudioApiClient].
class HttpStudioApiClient implements StudioApiClient {
  HttpStudioApiClient({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed$path').replace(queryParameters: query);
  }

  @override
  Future<FlowSnapshot> getFlow() async {
    final res = await _client.get(_uri('/flow'));
    _checkStatus(res);
    return FlowSnapshot.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<FlowSnapshot> saveDraft(FlowDefinition draft) async {
    final res = await _client.put(
      _uri('/flow/draft'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'draft': draft.toJson()}),
    );
    _checkStatus(res);
    return FlowSnapshot.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<FlowSnapshot> publish() async {
    final res = await _client.post(_uri('/flow/publish'));
    _checkStatus(res);
    return FlowSnapshot.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<FlowSnapshot> reset() async {
    final res = await _client.post(_uri('/flow/reset'));
    _checkStatus(res);
    return FlowSnapshot.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<Map<String, Object?>>> previewStep(String? stepId) async {
    final res = await _client.get(
      _uri('/flow/preview', stepId != null ? {'stepId': stepId} : null),
    );
    _checkStatus(res);
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final messages = (decoded['messages'] as List<dynamic>?) ?? const [];
    return [
      for (final item in messages)
        if (item is Map) item.cast<String, Object?>(),
    ];
  }

  @override
  Future<StudioAiEditResponse> aiEdit(String prompt) async {
    final res = await _client.post(
      _uri('/flow/ai-edit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': prompt}),
    );
    _checkStatus(res);
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioAiEditResponse(
      snapshot: FlowSnapshot.fromJson(decoded),
      summary: (decoded['aiSummary'] as String?) ?? 'Akış güncellendi.',
      usedRemoteLlm: (decoded['usedRemoteLlm'] as bool?) ?? false,
    );
  }

  @override
  Future<List<StudioSession>> getSessions() async {
    final res = await _client.get(_uri('/sessions'));
    _checkStatus(res);
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return [
      for (final raw in (decoded['sessions'] as List<dynamic>? ?? const []))
        StudioSession.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  @override
  Future<void> clearSessions() async {
    final res = await _client.delete(_uri('/sessions'));
    _checkStatus(res);
  }

  void _checkStatus(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'Sunucu hatası (HTTP ${res.statusCode})';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['message'] is String) {
          message = decoded['message'] as String;
        }
      } catch (_) {}
      throw Exception(message);
    }
  }

  @override
  void dispose() {
    _client.close();
  }
}

