import 'package:flow_core/flow_core.dart';

import 'a2ui_dsl.dart';

/// Compiled output for a step or summary screen.
class CompiledSurfacePayload {
  const CompiledSurfacePayload({
    required this.surfaceId,
    required this.messages,
  });

  final String surfaceId;
  final List<Map<String, Object?>> messages;
}

/// Compiles a [FlowDefinition] step or summary into A2UI v1.0 message envelopes.
class FlowCompiler {
  const FlowCompiler();

  /// Sanitizes an identifier so it is guaranteed to be a valid UAX #31 identifier
  /// for A2UI v1.0 component IDs.
  static String sanitizeId(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    if (cleaned.isEmpty) return 'item';
    if (RegExp(r'^[0-9]').hasMatch(cleaned)) {
      return 'c_$cleaned';
    }
    return cleaned;
  }

  /// Compiles a single [step] of [flow] into A2UI messages:
  /// `[if (previousSurfaceId != null) deleteSurface, createSurface, updateComponents]`.
  CompiledSurfacePayload compileStep({
    required FlowDefinition flow,
    required FlowStep step,
    required int flowVersion,
    required int nonce,
    Map<String, Object?> existingAnswers = const {},
    String? previousSurfaceId,
    String? sessionId,
  }) {
    final surfaceId = 'flow-${step.id}-$nonce';
    final stepSafeId = sanitizeId(step.id);

    // Build initial answers map merging existing answers with defaults for fields in this step
    final answers = <String, Object?>{
      ...existingAnswers,
    };
    for (final field in step.fields) {
      if (!answers.containsKey(field.key) || answers[field.key] == null) {
        answers[field.key] = _defaultInitialValue(field);
      }
    }

    final dataModel = <String, Object?>{
      'answers': answers,
      'formError': '',
      'meta': {
        'stepId': step.id,
        'flowVersion': flowVersion,
        if (sessionId != null) 'sessionId': sessionId,
      },
    };

    final components = <Map<String, Object?>>[];
    final rootChildren = <String>[];

    // Step progress indicator / header
    final stepIndex = flow.steps.indexWhere((s) => s.id == step.id);
    if (stepIndex >= 0 && flow.steps.length > 1) {
      final progressId = 'step_${stepSafeId}_progress';
      rootChildren.add(progressId);
      components.add({
        'id': progressId,
        'component': 'Text',
        'text': 'Adım ${stepIndex + 1} / ${flow.steps.length} • ${flow.title}',
        'variant': 'caption',
      });
    }

    // Step Title
    final titleId = 'step_${stepSafeId}_title';
    rootChildren.add(titleId);
    components.add({
      'id': titleId,
      'component': 'Text',
      'text': '## ${step.title}',
    });

    // Optional Description
    if (step.description != null && step.description!.trim().isNotEmpty) {
      final descId = 'step_${stepSafeId}_description';
      rootChildren.add(descId);
      components.add({
        'id': descId,
        'component': 'Text',
        'text': step.description!.trim(),
        'variant': 'caption',
      });
    }

    // Fields and button gating conditions
    final buttonGateConditions = <Map<String, Object?>>[];

    for (final field in step.fields) {
      final fieldId = 'field_${sanitizeId(field.key)}';
      rootChildren.add(fieldId);

      final compiledField = _compileField(
        field: field,
        componentId: fieldId,
        buttonGateConditions: buttonGateConditions,
      );
      components.add(compiledField);
    }

    // Server-side validation error text bound to /formError
    final errorId = 'step_${stepSafeId}_error';
    rootChildren.add(errorId);
    components.add({
      'id': errorId,
      'component': 'Text',
      'text': A2uiDsl.path('/formError'),
      'variant': 'caption',
    });

    // Submit Button + its child Text
    final submitTextId = 'step_${stepSafeId}_submit_label';
    final submitBtnId = 'step_${stepSafeId}_submit';
    rootChildren.add(submitBtnId);

    components.add({
      'id': submitTextId,
      'component': 'Text',
      'text': step.submitLabel.trim().isEmpty ? 'Devam Et' : step.submitLabel,
    });

    final buttonGate = A2uiDsl.combineConditionsWithAnd(buttonGateConditions);
    components.add({
      'id': submitBtnId,
      'component': 'Button',
      'child': submitTextId,
      'variant': 'primary',
      'action': {
        'event': {
          'name': 'submit_step',
          'context': {
            'stepId': step.id,
            'flowVersion': flowVersion,
          },
        },
      },
      if (buttonGate != null)
        A2uiDsl.checksKey: [
          A2uiDsl.checkRule(
            condition: buttonGate,
            message: 'Lütfen zorunlu alanları eksiksiz doldurun.',
          ),
        ],
    });

    // Root Column placed first in the list for readability
    final allComponents = <Map<String, Object?>>[
      {
        'id': 'root',
        'component': 'Column',
        'children': rootChildren,
      },
      ...components,
    ];

    final messages = <Map<String, Object?>>[
      if (previousSurfaceId != null && previousSurfaceId.isNotEmpty)
        A2uiDsl.deleteSurface(previousSurfaceId),
      A2uiDsl.createSurface(
        surfaceId: surfaceId,
        dataModel: dataModel,
        // Custom components only exist in our own catalog. Steps without
        // them stay on the basic catalog so any A2UI renderer can show them.
        catalogId: allComponents.any((c) =>
                A2uiDsl.flowCatalogComponents.contains(c['component']))
            ? A2uiDsl.flowCatalogId
            : A2uiDsl.basicCatalogId,
      ),
      A2uiDsl.updateComponents(
        surfaceId: surfaceId,
        components: allComponents,
      ),
    ];

    return CompiledSurfacePayload(
      surfaceId: surfaceId,
      messages: messages,
    );
  }

  /// Compiles the completion / summary screen when `next` resolves to `null`.
  CompiledSurfacePayload compileSummary({
    required FlowDefinition flow,
    required int flowVersion,
    required int nonce,
    required Map<String, Object?> answers,
    String? previousSurfaceId,
    String? sessionId,
  }) {
    final surfaceId = 'flow-summary-$nonce';

    final dataModel = <String, Object?>{
      'answers': answers,
      'formError': '',
      'meta': {
        'stepId': AnswerReconciler.summaryStepId,
        'flowVersion': flowVersion,
        if (sessionId != null) 'sessionId': sessionId,
      },
    };

    final components = <Map<String, Object?>>[];
    final rootChildren = <String>[];

    const titleId = 'summary_title';
    const subtitleId = 'summary_subtitle';
    rootChildren.addAll([titleId, subtitleId]);

    components.add({
      'id': titleId,
      'component': 'Text',
      'text': '## Kayıt Tamamlandı',
    });

    components.add({
      'id': subtitleId,
      'component': 'Text',
      'text': '${flow.title} yanıtlarınızın özeti aşağıdadır:',
      'variant': 'caption',
    });

    // Build a summary row for every field in the flow that has an answer
    var rowIndex = 0;
    for (final step in flow.steps) {
      for (final field in step.fields) {
        final rawVal = answers[field.key];
        final formatted = _formatAnswerForSummary(field, rawVal);
        final rowId = 'summary_item_${sanitizeId(field.key)}_$rowIndex';
        rowIndex++;
        rootChildren.add(rowId);
        components.add({
          'id': rowId,
          'component': 'Text',
          'text': '**${field.label}:** $formatted',
        });
      }
    }

    const dividerId = 'summary_divider';
    rootChildren.add(dividerId);
    components.add({
      'id': dividerId,
      'component': 'Divider',
    });

    const restartLabelId = 'summary_restart_label';
    const restartBtnId = 'summary_restart_btn';
    rootChildren.add(restartBtnId);

    components.add({
      'id': restartLabelId,
      'component': 'Text',
      'text': 'Baştan Başla',
    });

    components.add({
      'id': restartBtnId,
      'component': 'Button',
      'child': restartLabelId,
      'variant': 'primary',
      'action': {
        'event': {
          'name': 'restart',
          'context': {
            'flowVersion': flowVersion,
          },
        },
      },
    });

    final allComponents = <Map<String, Object?>>[
      {
        'id': 'root',
        'component': 'Column',
        'children': rootChildren,
      },
      ...components,
    ];

    final messages = <Map<String, Object?>>[
      if (previousSurfaceId != null && previousSurfaceId.isNotEmpty)
        A2uiDsl.deleteSurface(previousSurfaceId),
      A2uiDsl.createSurface(
        surfaceId: surfaceId,
        dataModel: dataModel,
      ),
      A2uiDsl.updateComponents(
        surfaceId: surfaceId,
        components: allComponents,
      ),
    ];

    return CompiledSurfacePayload(
      surfaceId: surfaceId,
      messages: messages,
    );
  }

  /// Compiles a server-side validation error update message for the active surface.
  Map<String, Object?> compileFormError({
    required String surfaceId,
    required String errorMessage,
  }) {
    return A2uiDsl.updateDataModel(
      surfaceId: surfaceId,
      path: '/formError',
      value: errorMessage,
    );
  }

  Object _defaultInitialValue(FlowField field) {
    return switch (field.type) {
      FieldType.text ||
      FieldType.longText ||
      FieldType.email ||
      FieldType.number ||
      FieldType.date ||
      FieldType.photo =>
        '',
      FieldType.singleChoice || FieldType.multiChoice => <String>[],
      FieldType.checkbox => false,
      FieldType.slider => field.min ?? 0,
    };
  }

  Map<String, Object?> _compileField({
    required FlowField field,
    required String componentId,
    required List<Map<String, Object?>> buttonGateConditions,
  }) {
    final boundPath = '/answers/${field.key}';
    final fieldChecks = <Map<String, Object?>>[];

    switch (field.type) {
      case FieldType.text:
        if (field.required) {
          final cond = A2uiDsl.requiredCall(boundPath);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: cond,
            message: '${field.label} alanı zorunludur.',
          ));
          buttonGateConditions.add(cond);
        }
        if (field.minLength != null && field.minLength! > 0) {
          final cond = A2uiDsl.lengthCall(boundPath, min: field.minLength);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: cond,
            message:
                '${field.label} en az ${field.minLength} karakter olmalıdır.',
          ));
          if (field.required) {
            buttonGateConditions.add(cond);
          }
        }
        return {
          'id': componentId,
          'component': 'TextField',
          'variant': 'shortText',
          'label': field.label,
          if (field.placeholder != null && field.placeholder!.isNotEmpty)
            'placeholder': field.placeholder,
          'value': A2uiDsl.path(boundPath),
          if (fieldChecks.isNotEmpty) A2uiDsl.checksKey: fieldChecks,
        };

      case FieldType.longText:
        if (field.required) {
          final cond = A2uiDsl.requiredCall(boundPath);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: cond,
            message: '${field.label} alanı zorunludur.',
          ));
          buttonGateConditions.add(cond);
        }
        if (field.minLength != null && field.minLength! > 0) {
          final cond = A2uiDsl.lengthCall(boundPath, min: field.minLength);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: cond,
            message:
                '${field.label} en az ${field.minLength} karakter olmalıdır.',
          ));
          if (field.required) {
            buttonGateConditions.add(cond);
          }
        }
        return {
          'id': componentId,
          'component': 'TextField',
          'variant': 'longText',
          'label': field.label,
          if (field.placeholder != null && field.placeholder!.isNotEmpty)
            'placeholder': field.placeholder,
          'value': A2uiDsl.path(boundPath),
          if (fieldChecks.isNotEmpty) A2uiDsl.checksKey: fieldChecks,
        };

      case FieldType.email:
        if (field.required) {
          final reqCond = A2uiDsl.requiredCall(boundPath);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: reqCond,
            message: '${field.label} alanı zorunludur.',
          ));
          buttonGateConditions.add(reqCond);
        }
        final emailCond = A2uiDsl.emailCall(boundPath);
        fieldChecks.add(A2uiDsl.checkRule(
          condition: emailCond,
          message: 'Geçerli bir e-posta adresi girin.',
        ));
        if (field.required) {
          buttonGateConditions.add(emailCond);
        }
        return {
          'id': componentId,
          'component': 'TextField',
          'variant': 'shortText',
          'label': field.label,
          if (field.placeholder != null && field.placeholder!.isNotEmpty)
            'placeholder': field.placeholder,
          'value': A2uiDsl.path(boundPath),
          A2uiDsl.checksKey: fieldChecks,
        };

      case FieldType.number:
        if (field.required) {
          final reqCond = A2uiDsl.requiredCall(boundPath);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: reqCond,
            message: '${field.label} alanı zorunludur.',
          ));
          buttonGateConditions.add(reqCond);
        }
        if (field.min != null || field.max != null) {
          final numCond = A2uiDsl.numericCall(
            boundPath,
            min: field.min,
            max: field.max,
          );
          fieldChecks.add(A2uiDsl.checkRule(
            condition: numCond,
            message: _numericRangeMessage(field),
          ));
          if (field.required) {
            buttonGateConditions.add(numCond);
          }
        }
        return {
          'id': componentId,
          'component': 'TextField',
          'variant': 'number',
          'label': field.label,
          if (field.placeholder != null && field.placeholder!.isNotEmpty)
            'placeholder': field.placeholder,
          'value': A2uiDsl.path(boundPath),
          if (fieldChecks.isNotEmpty) A2uiDsl.checksKey: fieldChecks,
        };

      case FieldType.date:
        if (field.required) {
          final reqCond = A2uiDsl.requiredCall(boundPath);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: reqCond,
            message: '${field.label} seçimi zorunludur.',
          ));
          buttonGateConditions.add(reqCond);
        }
        return {
          'id': componentId,
          'component': 'DateTimeInput',
          'label': field.label,
          'enableDate': true,
          'value': A2uiDsl.path(boundPath),
          if (fieldChecks.isNotEmpty) A2uiDsl.checksKey: fieldChecks,
        };

      case FieldType.singleChoice:
      case FieldType.multiChoice:
        if (field.required) {
          final reqCond = A2uiDsl.requiredCall(boundPath);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: reqCond,
            message: '${field.label} için seçim yapmalısınız.',
          ));
          buttonGateConditions.add(reqCond);
        }
        final options = [
          for (final opt in field.options ?? const <FieldOption>[])
            {
              'value': opt.value,
              'label': opt.label,
            },
        ];
        return {
          'id': componentId,
          'component': 'ChoicePicker',
          'label': field.label,
          'variant': field.type == FieldType.multiChoice
              ? 'multipleSelection'
              : 'mutuallyExclusive',
          'displayStyle': 'chips',
          'options': options,
          'value': A2uiDsl.path(boundPath),
          if (fieldChecks.isNotEmpty) A2uiDsl.checksKey: fieldChecks,
        };

      case FieldType.checkbox:
        if (field.required) {
          // For checkbox, required means the path itself evaluates to true
          final boolCond = A2uiDsl.path(boundPath);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: boolCond,
            message: '${field.label} onaylanmalıdır.',
          ));
          buttonGateConditions.add(boolCond);
        }
        return {
          'id': componentId,
          'component': 'CheckBox',
          'label': field.label,
          'value': A2uiDsl.path(boundPath),
          if (fieldChecks.isNotEmpty) A2uiDsl.checksKey: fieldChecks,
        };

      case FieldType.slider:
        final min = field.min ?? 0;
        final max = field.max ?? 100;
        return {
          'id': componentId,
          'component': 'Slider',
          'label': field.label,
          'min': min,
          'max': max,
          'value': A2uiDsl.path(boundPath),
        };

      case FieldType.photo:
        // Custom component: the Player's flow catalog draws it with
        // image_picker and writes the uploaded path (/uploads/<id>.jpg)
        // back to /answers/<key>.
        if (field.required) {
          final reqCond = A2uiDsl.requiredCall(boundPath);
          fieldChecks.add(A2uiDsl.checkRule(
            condition: reqCond,
            message: '${field.label} için bir fotoğraf seçin.',
          ));
          buttonGateConditions.add(reqCond);
        }
        return {
          'id': componentId,
          'component': 'PhotoPicker',
          'label': field.label,
          'value': A2uiDsl.path(boundPath),
          if (fieldChecks.isNotEmpty) A2uiDsl.checksKey: fieldChecks,
        };
    }
  }

  String _numericRangeMessage(FlowField field) {
    if (field.min != null && field.max != null) {
      return '${field.label} ${field.min} ile ${field.max} arasında olmalıdır.';
    }
    if (field.min != null) {
      return '${field.label} en az ${field.min} olmalıdır.';
    }
    return '${field.label} en fazla ${field.max} olmalıdır.';
  }

  String _formatAnswerForSummary(FlowField field, Object? rawVal) {
    if (rawVal == null) return '—';
    switch (field.type) {
      case FieldType.singleChoice:
      case FieldType.multiChoice:
        final List<String> values = switch (rawVal) {
          final List<Object?> l => l.whereType<String>().toList(),
          final String s when s.isNotEmpty => [s],
          _ => const [],
        };
        if (values.isEmpty) return '—';
        final labelMap = {
          for (final opt in field.options ?? const <FieldOption>[])
            opt.value: opt.label,
        };
        return values.map((v) => labelMap[v] ?? v).join(', ');
      case FieldType.checkbox:
        return rawVal == true ? 'Evet' : 'Hayır';
      case FieldType.photo:
        return rawVal is String && rawVal.isNotEmpty ? 'Yüklendi ✓' : '—';
      default:
        final str = rawVal.toString().trim();
        return str.isEmpty ? '—' : str;
    }
  }
}

