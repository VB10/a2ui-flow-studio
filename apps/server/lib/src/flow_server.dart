import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_compiler/flow_compiler.dart';
import 'package:flow_core/flow_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'ai_flow_assistant.dart';
import 'event_hub.dart';
import 'flow_agent.dart';
import 'flow_store.dart';
import 'submission_log.dart';
import 'upload_store.dart';

/// HTTP server handler wiring Studio REST endpoints, Player JSONL streams,
/// and SSE `/events`.
class FlowServer {
  factory FlowServer({
    required FlowStore store,
    FlowAgent? agent,
    FlowCompiler? compiler,
    EventHub? eventHub,
    AiFlowAssistant? aiAssistant,
    SubmissionLog? submissionLog,
    UploadStore? uploadStore,
    Duration streamDelay = const Duration(milliseconds: 120),
    bool enableLogging = true,
  }) {
    final log = submissionLog ?? agent?.submissionLog ?? SubmissionLog();
    return FlowServer._(
      store: store,
      agent: agent ?? FlowAgent(compiler: compiler, submissionLog: log),
      compiler: compiler ?? const FlowCompiler(),
      eventHub: eventHub ?? EventHub(),
      aiAssistant: aiAssistant ?? AiFlowAssistant(),
      submissionLog: log,
      uploadStore: uploadStore ?? UploadStore(),
      streamDelay: streamDelay,
      enableLogging: enableLogging,
    );
  }

  FlowServer._({
    required this.store,
    required this.agent,
    required this.compiler,
    required this.eventHub,
    required this.aiAssistant,
    required this.submissionLog,
    required this.uploadStore,
    required this.streamDelay,
    required this.enableLogging,
  }) {
    // Push every session change to SSE listeners (`event: submission`).
    // Players ignore this event; Studio or curl can follow it live.
    submissionLog.changes.listen(
      (session) => eventHub.broadcast('submission', {
        'sessionId': session.id,
        'status': session.status.jsonValue,
      }),
    );
  }

  final FlowStore store;
  final FlowAgent agent;
  final FlowCompiler compiler;
  final EventHub eventHub;
  final AiFlowAssistant aiAssistant;

  /// Observed Player submissions shown in Studio's "Gönderimler" tab.
  final SubmissionLog submissionLog;

  /// Photos uploaded by the Player's `PhotoPicker` (`POST /uploads`).
  final UploadStore uploadStore;

  /// Delay between JSONL envelopes so progressive A2UI rendering is visible.
  final Duration streamDelay;
  final bool enableLogging;

  Handler get handler {
    final router = Router()
      ..get('/health', _handleHealth)
      ..get('/events', _handleEvents)
      ..post('/a2ui/start', _handleA2uiStart)
      ..post('/a2ui/action', _handleA2uiAction)
      ..post('/a2ui/refresh', _handleA2uiRefresh)
      ..get('/flow', _handleGetFlow)
      ..put('/flow/draft', _handlePutDraft)
      ..post('/flow/publish', _handlePublish)
      ..post('/flow/reset', _handleReset)
      ..get('/flow/preview', _handlePreview)
      ..post('/flow/ai-edit', _handleAiEdit)
      ..get('/sessions', _handleGetSessions)
      ..delete('/sessions', _handleClearSessions)
      ..post('/uploads', _handleUpload)
      ..get('/uploads/<name>', _handleGetUpload);

    return Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_loggingMiddleware())
        .addHandler(router.call);
  }

  Future<Response> _handleHealth(Request request) async {
    return _jsonResponse({
      'status': 'ok',
      'publishedVersion': store.snapshot.publishedVersion,
      'connectedPlayers': eventHub.clientCount,
    });
  }

  Future<Response> _handleEvents(Request request) async {
    final byteStream = eventHub.subscribe(
      currentPublishedVersion: store.snapshot.publishedVersion,
    );

    return Response.ok(
      byteStream,
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no',
      },
      context: {
        'shelf.io.buffer_output': false,
      },
    );
  }

  Future<Response> _handleA2uiStart(Request request) async {
    try {
      final body = await _readJsonBodyOrEmpty(request);
      final previousSurfaceId = body['surfaceId'] as String?;
      final messages = agent.handleStart(
        snapshot: store.snapshot,
        previousSurfaceId: previousSurfaceId,
      );
      return _streamJsonlMessages(messages);
    } on FlowAgentClientException catch (e) {
      return _jsonResponse(e.toJson(), statusCode: e.statusCode);
    }
  }

  Future<Response> _handleA2uiAction(Request request) async {
    try {
      final body = await _readJsonBodyOrEmpty(request);
      final messages = agent.handleAction(
        snapshot: store.snapshot,
        requestBody: body,
      );
      return _streamJsonlMessages(messages);
    } on FlowAgentClientException catch (e) {
      return _jsonResponse(e.toJson(), statusCode: e.statusCode);
    }
  }

  Future<Response> _handleA2uiRefresh(Request request) async {
    try {
      final body = await _readJsonBodyOrEmpty(request);
      final messages = agent.handleRefresh(
        snapshot: store.snapshot,
        requestBody: body,
      );
      return _streamJsonlMessages(messages);
    } on FlowAgentClientException catch (e) {
      return _jsonResponse(e.toJson(), statusCode: e.statusCode);
    }
  }

  Future<Response> _handleGetFlow(Request request) async {
    return _jsonResponse(store.snapshot.toJson());
  }

  Future<Response> _handlePutDraft(Request request) async {
    try {
      final body = await _readJsonBodyOrEmpty(request);
      final draftJson = body.containsKey('draft') && body['draft'] is Map
          ? Map<String, dynamic>.from(body['draft'] as Map)
          : body;
      final newDraft = FlowDefinition.fromJson(draftJson);
      final updated = store.saveDraft(newDraft);
      final issues = FlowValidator.validateFlow(updated.draft);
      return _jsonResponse({
        ...updated.toJson(),
        'validationIssues': issues.map((i) => i.toJson()).toList(),
      });
    } catch (e) {
      return _jsonResponse(
        {
          'code': 'invalid_draft_body',
          'message': 'Geçersiz draft verisi: $e',
        },
        statusCode: 400,
      );
    }
  }

  Future<Response> _handlePublish(Request request) async {
    try {
      final updated = store.publish();
      eventHub.broadcastPublished(updated.publishedVersion);
      return _jsonResponse(updated.toJson());
    } on FlowPublishValidationException catch (e) {
      return _jsonResponse(
        {
          'code': 'validation_failed',
          'message': 'Yayınlama doğrulama hatası nedeniyle reddedildi.',
          'issues': e.issues.map((i) => i.toJson()).toList(),
        },
        statusCode: 422,
      );
    }
  }

  Future<Response> _handleReset(Request request) async {
    final updated = store.resetToTemplate();
    eventHub.broadcastPublished(updated.publishedVersion);
    return _jsonResponse(updated.toJson());
  }

  Future<Response> _handlePreview(Request request) async {
    final draft = store.snapshot.draft;
    if (draft.steps.isEmpty) {
      return _jsonResponse({
        'stepId': null,
        'messages': const <Object?>[],
      });
    }

    final requestedStepId = request.url.queryParameters['stepId'];
    if (requestedStepId == AnswerReconciler.summaryStepId) {
      final compiled = compiler.compileSummary(
        flow: draft,
        flowVersion: store.snapshot.publishedVersion,
        nonce: 1,
        answers: const {},
      );
      return _jsonResponse({
        'stepId': AnswerReconciler.summaryStepId,
        'surfaceId': compiled.surfaceId,
        'messages': compiled.messages,
      });
    }

    final step = (requestedStepId != null
            ? draft.stepById(requestedStepId)
            : null) ??
        draft.steps.first;

    final compiled = compiler.compileStep(
      flow: draft,
      step: step,
      flowVersion: store.snapshot.publishedVersion,
      nonce: 1,
    );

    return _jsonResponse({
      'stepId': step.id,
      'surfaceId': compiled.surfaceId,
      'messages': compiled.messages,
    });
  }

  Future<Response> _handleGetSessions(Request request) async {
    return _jsonResponse(submissionLog.toJson());
  }

  Future<Response> _handleClearSessions(Request request) async {
    submissionLog.clear();
    return _jsonResponse(submissionLog.toJson());
  }

  /// Body: raw image bytes. Content-Type: image/jpeg | png | webp | gif.
  /// Response: `{"path": "/uploads/p_xxx.jpg"}`.
  Future<Response> _handleUpload(Request request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      builder.add(chunk);
      if (builder.length > uploadStore.maxBytes) {
        return _jsonResponse({'error': 'Dosya çok büyük.'}, statusCode: 413);
      }
    }
    try {
      final path = uploadStore.save(
        builder.takeBytes(),
        request.headers['content-type'],
      );
      return _jsonResponse({'path': path});
    } on UploadException catch (e) {
      return _jsonResponse({'error': e.message}, statusCode: 400);
    }
  }

  Future<Response> _handleGetUpload(Request request, String name) async {
    final file = uploadStore.read(name);
    if (file == null) return Response.notFound('Not found');
    return Response.ok(
      file.bytes,
      headers: {
        'Content-Type': file.contentType,
        'Cache-Control': 'public, max-age=31536000, immutable',
      },
    );
  }

  Future<Response> _handleAiEdit(Request request) async {
    try {
      final body = await _readJsonBodyOrEmpty(request);
      final prompt = (body['prompt'] as String?) ?? '';
      if (prompt.trim().isEmpty) {
        return _jsonResponse(
          {
            'code': 'empty_prompt',
            'message': 'Prompt metni boş olamaz.',
          },
          statusCode: 400,
        );
      }

      final result = await aiAssistant.applyPrompt(
        currentFlow: store.snapshot.draft,
        prompt: prompt,
      );
      final updatedSnapshot = store.saveDraft(result.flow);
      final issues = FlowValidator.validateFlow(updatedSnapshot.draft);

      return _jsonResponse({
        ...updatedSnapshot.toJson(),
        'aiSummary': result.summary,
        'usedRemoteLlm': result.usedRemoteLlm,
        'validationIssues': issues.map((i) => i.toJson()).toList(),
      });
    } catch (e) {
      return _jsonResponse(
        {
          'code': 'ai_edit_failed',
          'message': 'AI düzenleme hatası: $e',
        },
        statusCode: 500,
      );
    }
  }

  Response _streamJsonlMessages(List<Map<String, Object?>> messages) {
    Stream<List<int>> generateChunks() async* {
      for (var i = 0; i < messages.length; i++) {
        if (i > 0 && streamDelay > Duration.zero) {
          await Future<void>.delayed(streamDelay);
        }
        final line = '${jsonEncode(messages[i])}\n';
        yield utf8.encode(line);
      }
    }

    return Response.ok(
      generateChunks(),
      headers: {
        'Content-Type': 'application/jsonl; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        'X-Streamed-Messages': messages.length.toString(),
      },
      context: {
        'shelf.io.buffer_output': false,
        'streamed_message_count': messages.length,
      },
    );
  }

  Response _jsonResponse(
    Map<String, Object?> body, {
    int statusCode = 200,
  }) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
      },
    );
  }

  Future<Map<String, dynamic>> _readJsonBodyOrEmpty(Request request) async {
    final text = await request.readAsString();
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw const FormatException('JSON body must be an object.');
  }

  Middleware _corsMiddleware() {
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Cache-Control',
      'Access-Control-Expose-Headers': 'X-Streamed-Messages',
    };

    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(headers: corsHeaders);
      };
    };
  }

  Middleware _loggingMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final sw = Stopwatch()..start();
        final response = await innerHandler(request);
        sw.stop();
        if (enableLogging) {
          final msgCount = response.context['streamed_message_count'] ??
              response.headers['X-Streamed-Messages'] ??
              '-';
          print(
            '[A2UI Server] ${request.method.padRight(6)} /${request.url.path.padRight(16)} '
            '-> ${response.statusCode} (${sw.elapsedMilliseconds}ms, messages: $msgCount)',
          );
        }
        return response;
      };
    };
  }
}

