import 'flow_models.dart';

/// A single validation issue preventing a flow from being published.
class FlowValidationIssue {
  const FlowValidationIssue({
    required this.code,
    required this.message,
    this.stepId,
    this.fieldKey,
  });

  final String code;
  final String message;
  final String? stepId;
  final String? fieldKey;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (stepId != null) 'stepId': stepId,
        if (fieldKey != null) 'fieldKey': fieldKey,
      };

  @override
  String toString() =>
      '[${stepId ?? "flow"}${fieldKey != null ? "/$fieldKey" : ""}] $message';
}

/// Validates a [FlowDefinition] before publishing (shared by Studio and Server)
/// and validates user answers on step submission.
/// Prefix of photo paths the server hands out from `POST /uploads`.
const String kUploadPathPrefix = '/uploads/';

/// True when [value] is a photo path the server stored, e.g.
/// `/uploads/p_abc123.jpg`. Rejects traversal and foreign URLs.
bool isUploadedPhotoPath(String value) =>
    RegExp(r'^/uploads/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|gif)$')
        .hasMatch(value.trim());

abstract final class FlowValidator {
  static final RegExp _emailRegex =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

  /// Validates the structural integrity of [flow] before publishing.
  static List<FlowValidationIssue> validateFlow(FlowDefinition flow) {
    final issues = <FlowValidationIssue>[];

    if (flow.title.trim().isEmpty) {
      issues.add(const FlowValidationIssue(
        code: 'empty_flow_title',
        message: 'Akış başlığı boş olamaz.',
      ));
    }

    if (flow.steps.isEmpty) {
      issues.add(const FlowValidationIssue(
        code: 'no_steps',
        message: 'Akışta en az bir adım olmalıdır.',
      ));
      return issues;
    }

    final seenStepIds = <String>{};
    final seenFieldKeys = <String>{};

    for (final step in flow.steps) {
      if (step.id.trim().isEmpty) {
        issues.add(const FlowValidationIssue(
          code: 'empty_step_id',
          message: 'Adım kimliği (id) boş olamaz.',
        ));
      } else if (!seenStepIds.add(step.id)) {
        issues.add(FlowValidationIssue(
          code: 'duplicate_step_id',
          message: 'Adım kimliği "${step.id}" birden fazla kez kullanılmış.',
          stepId: step.id,
        ));
      }

      if (step.title.trim().isEmpty) {
        issues.add(FlowValidationIssue(
          code: 'empty_step_title',
          message: '"${step.id}" adımının başlığı boş olamaz.',
          stepId: step.id,
        ));
      }

      for (final field in step.fields) {
        if (field.key.trim().isEmpty) {
          issues.add(FlowValidationIssue(
            code: 'empty_field_key',
            message: '"${step.title}" adımında anahtarsız (key) alan var.',
            stepId: step.id,
          ));
        } else if (!seenFieldKeys.add(field.key)) {
          issues.add(FlowValidationIssue(
            code: 'duplicate_field_key',
            message:
                'Alan anahtarı "${field.key}" akış içinde benzersiz olmalıdır.',
            stepId: step.id,
            fieldKey: field.key,
          ));
        }

        if (field.label.trim().isEmpty) {
          issues.add(FlowValidationIssue(
            code: 'empty_field_label',
            message: '"${field.key}" alanı için etiket (label) zorunludur.',
            stepId: step.id,
            fieldKey: field.key,
          ));
        }

        if (field.type.isChoice) {
          final opts = field.options ?? const [];
          if (opts.length < 2) {
            issues.add(FlowValidationIssue(
              code: 'insufficient_options',
              message:
                  '"${field.label}" seçim alanında en az 2 seçenek olmalıdır.',
              stepId: step.id,
              fieldKey: field.key,
            ));
          } else {
            final seenValues = <String>{};
            for (final opt in opts) {
              if (opt.value.trim().isEmpty || opt.label.trim().isEmpty) {
                issues.add(FlowValidationIssue(
                  code: 'empty_option',
                  message:
                      '"${field.label}" alanındaki tüm seçeneklerin değer ve etiketi dolu olmalıdır.',
                  stepId: step.id,
                  fieldKey: field.key,
                ));
              } else if (!seenValues.add(opt.value)) {
                issues.add(FlowValidationIssue(
                  code: 'duplicate_option_value',
                  message:
                      '"${field.label}" alanında "${opt.value}" seçeneği tekrar ediyor.',
                  stepId: step.id,
                  fieldKey: field.key,
                ));
              }
            }
          }
        }

        if (field.type == FieldType.slider) {
          final max = field.max;
          final min = field.min ?? 0;
          if (max == null) {
            issues.add(FlowValidationIssue(
              code: 'slider_missing_max',
              message: '"${field.label}" slider alanında maksimum değer zorunludur.',
              stepId: step.id,
              fieldKey: field.key,
            ));
          } else if (min >= max) {
            issues.add(FlowValidationIssue(
              code: 'slider_invalid_range',
              message:
                  '"${field.label}" slider alanında min ($min) < max ($max) olmalıdır.',
              stepId: step.id,
              fieldKey: field.key,
            ));
          }
        }

        if (field.type == FieldType.number &&
            field.min != null &&
            field.max != null &&
            field.min! > field.max!) {
          issues.add(FlowValidationIssue(
            code: 'number_invalid_range',
            message:
                '"${field.label}" sayı alanında min (${field.min}) <= max (${field.max}) olmalıdır.',
            stepId: step.id,
            fieldKey: field.key,
          ));
        }
      }
    }

    // Check next references and cycles
    final stepById = {for (final s in flow.steps) s.id: s};
    for (final step in flow.steps) {
      final defaultNext = step.next.defaultStepId;
      if (defaultNext != null && !stepById.containsKey(defaultNext)) {
        issues.add(FlowValidationIssue(
          code: 'unknown_next_step',
          message:
              '"${step.title}" adımı var olmayan "$defaultNext" adımına işaret ediyor.',
          stepId: step.id,
        ));
      }

      for (final rule in step.next.rules) {
        if (!stepById.containsKey(rule.goToStepId)) {
          issues.add(FlowValidationIssue(
            code: 'unknown_branch_step',
            message:
                '"${step.title}" adımındaki kural var olmayan "${rule.goToStepId}" adımına işaret ediyor.',
            stepId: step.id,
          ));
        }
        if (rule.fieldKey.trim().isEmpty ||
            !seenFieldKeys.contains(rule.fieldKey)) {
          issues.add(FlowValidationIssue(
            code: 'unknown_branch_field',
            message:
                '"${step.title}" adımındaki kural var olmayan "${rule.fieldKey}" alanına bağlı.',
            stepId: step.id,
          ));
        }
      }
    }

    // Cycle detection using DFS
    final visiting = <String>{};
    final visited = <String>{};

    bool hasCycle(String currentId) {
      if (visiting.contains(currentId)) return true;
      if (visited.contains(currentId)) return false;

      visiting.add(currentId);
      final step = stepById[currentId];
      if (step != null) {
        final targets = <String>[
          if (step.next.defaultStepId != null) step.next.defaultStepId!,
          for (final r in step.next.rules) r.goToStepId,
        ];
        for (final target in targets) {
          if (stepById.containsKey(target) && hasCycle(target)) {
            return true;
          }
        }
      }
      visiting.remove(currentId);
      visited.add(currentId);
      return false;
    }

    for (final step in flow.steps) {
      if (hasCycle(step.id)) {
        issues.add(FlowValidationIssue(
          code: 'step_cycle_detected',
          message:
              'Adım geçişlerinde döngü (cycle) tespit edildi ("${step.title}").',
          stepId: step.id,
        ));
        break;
      }
    }

    return issues;
  }

  /// Validates the user's [answers] for a single [step] on the server side.
  /// Returns a human-readable error message if validation fails, or `null` if valid.
  static String? validateStepSubmission(
    FlowStep step,
    Map<String, Object?> answers,
  ) {
    for (final field in step.fields) {
      final rawValue = answers[field.key];

      final isEmpty = _isEmptyAnswer(field.type, rawValue);
      if (field.required && isEmpty) {
        return '"${field.label}" alanı zorunludur.';
      }

      if (isEmpty) continue;

      switch (field.type) {
        case FieldType.text:
        case FieldType.longText:
          if (rawValue is! String) {
            return '"${field.label}" alanı metin olmalıdır.';
          }
          if (field.minLength != null && rawValue.length < field.minLength!) {
            return '"${field.label}" en az ${field.minLength} karakter olmalıdır.';
          }

        case FieldType.email:
          if (rawValue is! String || !_emailRegex.hasMatch(rawValue.trim())) {
            return '"${field.label}" için geçerli bir e-posta adresi girin.';
          }

        case FieldType.number:
          final num? parsed = switch (rawValue) {
            final num n => n,
            final String s => num.tryParse(s.trim()),
            _ => null,
          };
          if (parsed == null || parsed.isNaN) {
            return '"${field.label}" alanı geçerli bir sayı olmalıdır.';
          }
          if (field.min != null && parsed < field.min!) {
            return '"${field.label}" en az ${field.min} olmalıdır.';
          }
          if (field.max != null && parsed > field.max!) {
            return '"${field.label}" en fazla ${field.max} olmalıdır.';
          }

        case FieldType.photo:
          if (rawValue is! String || !isUploadedPhotoPath(rawValue)) {
            return '"${field.label}" için geçerli bir fotoğraf yükleyin.';
          }

        case FieldType.slider:
          final num? parsed = switch (rawValue) {
            final num n => n,
            final String s => num.tryParse(s.trim()),
            _ => null,
          };
          if (parsed == null || parsed.isNaN) {
            return '"${field.label}" alanı geçerli bir sayı olmalıdır.';
          }
          final min = field.min ?? 0;
          if (parsed < min) {
            return '"${field.label}" en az $min olmalıdır.';
          }
          if (field.max != null && parsed > field.max!) {
            return '"${field.label}" en fazla ${field.max} olmalıdır.';
          }

        case FieldType.date:
          if (rawValue is! String || DateTime.tryParse(rawValue) == null) {
            return '"${field.label}" için geçerli bir tarih seçin.';
          }

        case FieldType.singleChoice:
        case FieldType.multiChoice:
          final List<String> selected = switch (rawValue) {
            final List<Object?> list => list.whereType<String>().toList(),
            final String s when s.isNotEmpty => [s],
            _ => const [],
          };
          if (field.type == FieldType.singleChoice && selected.length > 1) {
            return '"${field.label}" alanında yalnızca tek seçim yapılabilir.';
          }
          final allowed =
              (field.options ?? const []).map((o) => o.value).toSet();
          for (final item in selected) {
            if (!allowed.contains(item)) {
              return '"${field.label}" alanında geçersiz seçenek: "$item".';
            }
          }

        case FieldType.checkbox:
          if (rawValue is! bool) {
            return '"${field.label}" alanı geçerli bir onay değeri olmalıdır.';
          }
          if (field.required && !rawValue) {
            return '"${field.label}" kutusunu onaylamanız gerekiyor.';
          }
      }
    }
    return null;
  }

  static bool _isEmptyAnswer(FieldType type, Object? value) {
    if (value == null) return true;
    return switch (type) {
      FieldType.text ||
      FieldType.longText ||
      FieldType.email ||
      FieldType.date ||
      FieldType.photo =>
        value is! String || value.trim().isEmpty,
      FieldType.number => switch (value) {
          final String s => s.trim().isEmpty,
          final num n => n.isNaN,
          _ => true,
        },
      FieldType.slider => switch (value) {
          final num n => n.isNaN,
          final String s => s.trim().isEmpty,
          _ => true,
        },
      FieldType.singleChoice || FieldType.multiChoice => switch (value) {
          final List<Object?> l => l.whereType<String>().isEmpty,
          final String s => s.trim().isEmpty,
          _ => true,
        },
      FieldType.checkbox => value != true,
    };
  }

  /// Resolves the next step ID after [step] given [answers].
  /// Returns `null` when the flow finishes (summary screen).
  static String? resolveNextStepId(
    FlowStep step,
    Map<String, Object?> answers,
  ) {
    for (final rule in step.next.rules) {
      final raw = answers[rule.fieldKey];
      final matches = switch (raw) {
        final List<Object?> list =>
          list.map((e) => e?.toString()).contains(rule.equals),
        final Object v => v.toString() == rule.equals,
        null => false,
      };
      if (matches) {
        return rule.goToStepId;
      }
    }
    return step.next.defaultStepId;
  }
}

