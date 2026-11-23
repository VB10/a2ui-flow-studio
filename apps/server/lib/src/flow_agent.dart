import 'package:flow_compiler/flow_compiler.dart';
import 'package:flow_core/flow_core.dart';

import 'submission_log.dart';

/// Typed exception for 4xx client errors in [FlowAgent].
class FlowAgentClientException implements Exception {
  const FlowAgentClientException({
    required this.code,
    required this.message,
    this.statusCode = 400,
  });

  final String code;
  final String message;
  final int statusCode;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
      };
}

/// Stateless agent that compiles A2UI message sequences for `/a2ui/start`,
/// `/a2ui/action`, and `/a2ui/refresh`.
class FlowAgent {
  FlowAgent({
    FlowCompiler? compiler,
    this.submissionLog,
  }) : _compiler = compiler ?? const FlowCompiler();

  final FlowCompiler _compiler;

  /// Optional observer that records what Players submit (Studio "Gönderimler").
  final SubmissionLog? submissionLog;
  int _nonceCounter = 0;

  int _nextNonce() => ++_nonceCounter;

  /// Starts the onboarding flow from its first step.
  List<Map<String, Object?>> handleStart({
    required FlowSnapshot snapshot,
    String? previousSurfaceId,
    String? previousSessionId,
  }) {
    final flow = snapshot.published;
    if (flow.steps.isEmpty) {
      throw const FlowAgentClientException(
        code: 'empty_flow',
        message: 'Yayınlanmış akışta adım bulunamadı.',
      );
    }

    // Every start (and every restart) is a brand-new session.
    final sessionId = submissionLog?.startSession(
      flowVersion: snapshot.publishedVersion,
      stepId: flow.steps.first.id,
      previousSurfaceId: previousSurfaceId,
      previousSessionId: previousSessionId,
    );

    final compiled = _compiler.compileStep(
      flow: flow,
      step: flow.steps.first,
      flowVersion: snapshot.publishedVersion,
      nonce: _nextNonce(),
      previousSurfaceId: previousSurfaceId,
      sessionId: sessionId,
    );
    _attach(sessionId, compiled.surfaceId);
    return compiled.messages;
  }

  void _attach(String? sessionId, String surfaceId) {
    if (sessionId != null) submissionLog?.attachSurface(sessionId, surfaceId);
  }

  /// Processes a renderer action (`submit_step` or `restart`).
  List<Map<String, Object?>> handleAction({
    required FlowSnapshot snapshot,
    required Map<String, dynamic> requestBody,
  }) {
    final actionMap = requestBody['action'];
    if (actionMap is! Map) {
      throw const FlowAgentClientException(
        code: 'invalid_action_payload',
        message: 'İstek gövdesinde geçerli bir "action" nesnesi bulunamadı.',
      );
    }

    final actionName = actionMap['name'] as String?;
    final surfaceId = actionMap['surfaceId'] as String?;
    if (actionName == null || surfaceId == null || surfaceId.isEmpty) {
      throw const FlowAgentClientException(
        code: 'missing_action_fields',
        message: '"action.name" ve "action.surfaceId" zorunludur.',
      );
    }

    final context = (actionMap['context'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};

    final surfaceData = _extractSurfaceDataModel(
      requestBody['metadata'],
      surfaceId: surfaceId,
    );
    final rawAnswers =
        (surfaceData['answers'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{};
    final meta = (surfaceData['meta'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};

    final clientVersion = (context['flowVersion'] as num?)?.toInt() ??
        (meta['flowVersion'] as num?)?.toInt();

    final currentStepId =
        (context['stepId'] as String?) ?? (meta['stepId'] as String?);
    final sessionId = meta['sessionId'] as String?;

    if (actionName == 'restart') {
      return handleStart(
        snapshot: snapshot,
        previousSurfaceId: surfaceId,
        previousSessionId: sessionId,
      );
    }

    if (actionName != 'submit_step') {
      throw FlowAgentClientException(
        code: 'unknown_action',
        message: 'Bilinmeyen aksiyon: "$actionName".',
      );
    }

    // Section 6.3 rule 2: If flowVersion is stale, do not process the action;
    // apply the refresh behavior instead.
    if (clientVersion != null && clientVersion != snapshot.publishedVersion) {
      return _compileReconciledRefresh(
        snapshot: snapshot,
        currentStepId: currentStepId,
        currentAnswers: rawAnswers,
        previousSurfaceId: surfaceId,
        sessionId: sessionId,
      );
    }

    if (currentStepId == null || currentStepId.isEmpty) {
      throw const FlowAgentClientException(
        code: 'missing_step_id',
        message: '"stepId" bilgisi eksik.',
      );
    }

    final flow = snapshot.published;
    final step = flow.stepById(currentStepId);
    if (step == null) {
      throw FlowAgentClientException(
        code: 'unknown_step',
        message: 'Adım bulunamadı: "$currentStepId".',
      );
    }

    // Section 6.3 rule 3 & 4: Server-side validation of step fields
    final validationError = FlowValidator.validateStepSubmission(
      step,
      rawAnswers,
    );
    if (sessionId != null) {
      submissionLog?.recordSubmit(
        sessionId: sessionId,
        stepId: step.id,
        flowVersion: snapshot.publishedVersion,
        answers: rawAnswers,
        error: validationError,
      );
    }
    if (validationError != null) {
      return [
        _compiler.compileFormError(
          surfaceId: surfaceId,
          errorMessage: validationError,
        ),
      ];
    }

    // Determine next step (including branch rules)
    final nextStepId = FlowValidator.resolveNextStepId(step, rawAnswers);
    final nextStep = nextStepId == null ? null : flow.stepById(nextStepId);
    if (nextStep == null) {
      // Flow finished (or target step missing) -> summary screen.
      if (sessionId != null) {
        submissionLog?.markCompleted(
          sessionId: sessionId,
          flowVersion: snapshot.publishedVersion,
          answers: rawAnswers,
        );
      }
      final summary = _compiler.compileSummary(
        flow: flow,
        flowVersion: snapshot.publishedVersion,
        nonce: _nextNonce(),
        answers: rawAnswers,
        previousSurfaceId: surfaceId,
        sessionId: sessionId,
      );
      _attach(sessionId, summary.surfaceId);
      return summary.messages;
    }

    final compiledNext = _compiler.compileStep(
      flow: flow,
      step: nextStep,
      flowVersion: snapshot.publishedVersion,
      nonce: _nextNonce(),
      existingAnswers: rawAnswers,
      previousSurfaceId: surfaceId,
      sessionId: sessionId,
    );
    _attach(sessionId, compiledNext.surfaceId);
    return compiledNext.messages;
  }

  /// Refreshes the player's current step against the latest published version,
  /// reconciling answers via [AnswerReconciler].
  List<Map<String, Object?>> handleRefresh({
    required FlowSnapshot snapshot,
    required Map<String, dynamic> requestBody,
  }) {
    final surfaceId = requestBody['surfaceId'] as String?;
    final explicitStepId = requestBody['stepId'] as String?;

    final surfaceData = _extractSurfaceDataModel(
      requestBody['metadata'],
      surfaceId: surfaceId,
    );
    final rawAnswers = (requestBody['answers'] as Map?)?.cast<String, Object?>() ??
        (surfaceData['answers'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final meta = (surfaceData['meta'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};

    final currentStepId = explicitStepId ?? (meta['stepId'] as String?);

    return _compileReconciledRefresh(
      snapshot: snapshot,
      currentStepId: currentStepId,
      currentAnswers: rawAnswers,
      previousSurfaceId: surfaceId,
      sessionId: meta['sessionId'] as String?,
    );
  }

  List<Map<String, Object?>> _compileReconciledRefresh({
    required FlowSnapshot snapshot,
    required String? currentStepId,
    required Map<String, Object?> currentAnswers,
    required String? previousSurfaceId,
    String? sessionId,
  }) {
    final flow = snapshot.published;
    final reconciled = AnswerReconciler.reconcile(
      newFlow: flow,
      currentStepId: currentStepId,
      currentAnswers: currentAnswers,
    );

    final CompiledSurfacePayload compiled;
    if (reconciled.isSummary || reconciled.targetStepId == null) {
      compiled = _compiler.compileSummary(
        flow: flow,
        flowVersion: snapshot.publishedVersion,
        nonce: _nextNonce(),
        answers: reconciled.answers,
        previousSurfaceId: previousSurfaceId,
        sessionId: sessionId,
      );
    } else {
      final targetStep =
          flow.stepById(reconciled.targetStepId!) ?? flow.steps.first;
      compiled = _compiler.compileStep(
        flow: flow,
        step: targetStep,
        flowVersion: snapshot.publishedVersion,
        nonce: _nextNonce(),
        existingAnswers: reconciled.answers,
        previousSurfaceId: previousSurfaceId,
        sessionId: sessionId,
      );
    }
    _attach(sessionId, compiled.surfaceId);
    return compiled.messages;
  }

  /// Extracts `{answers, meta, ...}` for [surfaceId] from
  /// `metadata.a2uiRendererDataModel` (or `metadata.a2uiClientDataModel`).
  Map<String, Object?> _extractSurfaceDataModel(
    Object? rawMetadata, {
    required String? surfaceId,
  }) {
    if (rawMetadata is! Map) return const {};
    final rendererModel = rawMetadata['a2uiRendererDataModel'] ??
        rawMetadata['a2uiClientDataModel'];
    if (rendererModel is! Map) return const {};

    final surfaces = rendererModel['surfaces'];
    if (surfaces is! Map) return const {};

    if (surfaceId != null && surfaces[surfaceId] is Map) {
      return (surfaces[surfaceId] as Map).cast<String, Object?>();
    }
    if (surfaces.values.isNotEmpty && surfaces.values.first is Map) {
      return (surfaces.values.first as Map).cast<String, Object?>();
    }
    return const {};
  }
}

