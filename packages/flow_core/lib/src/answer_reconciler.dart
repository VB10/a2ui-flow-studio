import 'flow_models.dart';

/// Result of reconciling a player's current step and answers with a newly
/// published [FlowDefinition].
class ReconciledSession {
  const ReconciledSession({
    required this.targetStepId,
    required this.isSummary,
    required this.answers,
  });

  /// The step ID the player should render, or `null` if on the summary screen.
  final String? targetStepId;

  /// True when the player should render the summary screen.
  final bool isSummary;

  /// Cleaned and reconciled answers map.
  final Map<String, Object?> answers;
}

/// Pure function that reconciles existing user answers and step position
/// when a new version of [FlowDefinition] is published (Section 7 rules).
abstract final class AnswerReconciler {
  static const String summaryStepId = '__summary__';

  /// Reconciles [currentStepId] and [currentAnswers] against [newFlow].
  ///
  /// Rules:
  /// - Field added: starts empty/default; other answers are preserved.
  /// - Field deleted: its answer is removed from the data model.
  /// - Label or placeholder changed: answer is preserved.
  /// - Field type changed (incompatible): answer is dropped.
  /// - Choice option deleted: that option value is removed from the answer list.
  /// - Current step deleted: falls back to the first step, preserving matching answers.
  /// - User is on summary screen (`currentStepId == '__summary__'`): stays on summary
  ///   with reconciled answers (unless flow has no steps).
  static ReconciledSession reconcile({
    required FlowDefinition newFlow,
    required String? currentStepId,
    required Map<String, Object?> currentAnswers,
  }) {
    final fieldsByKey = <String, FlowField>{};
    for (final step in newFlow.steps) {
      for (final field in step.fields) {
        fieldsByKey[field.key] = field;
      }
    }

    final cleanedAnswers = <String, Object?>{};

    for (final entry in currentAnswers.entries) {
      final field = fieldsByKey[entry.key];
      if (field == null) {
        // Field was deleted -> drop answer
        continue;
      }

      final reconciledValue = _reconcileValueForField(field, entry.value);
      if (reconciledValue != null) {
        cleanedAnswers[entry.key] = reconciledValue;
      }
    }

    if (currentStepId == summaryStepId) {
      return ReconciledSession(
        targetStepId: null,
        isSummary: true,
        answers: cleanedAnswers,
      );
    }

    final stepExists = currentStepId != null &&
        newFlow.steps.any((step) => step.id == currentStepId);

    final resolvedStepId = stepExists
        ? currentStepId
        : (newFlow.steps.isNotEmpty ? newFlow.steps.first.id : null);

    return ReconciledSession(
      targetStepId: resolvedStepId,
      isSummary: resolvedStepId == null,
      answers: cleanedAnswers,
    );
  }

  static Object? _reconcileValueForField(FlowField field, Object? value) {
    if (value == null) return null;

    switch (field.type) {
      case FieldType.text:
      case FieldType.longText:
      case FieldType.email:
      case FieldType.photo:
        // Only preserve if it was already a String (and not a number/bool/list)
        if (value is String) return value;
        return null;

      case FieldType.number:
        // TextField variant 'number' binds to a String in A2UI
        if (value is String && num.tryParse(value.trim()) != null) {
          return value.trim();
        }
        return null;

      case FieldType.date:
        if (value is String && DateTime.tryParse(value) != null) {
          return value;
        }
        return null;

      case FieldType.singleChoice:
        if (value is! List) return null;
        final allowed =
            (field.options ?? const []).map((o) => o.value).toSet();
        final filtered = value
            .whereType<String>()
            .where(allowed.contains)
            .take(1)
            .toList();
        return filtered;

      case FieldType.multiChoice:
        if (value is! List) return null;
        final allowed =
            (field.options ?? const []).map((o) => o.value).toSet();
        final filtered =
            value.whereType<String>().where(allowed.contains).toList();
        return filtered;

      case FieldType.checkbox:
        if (value is bool) return value;
        return null;

      case FieldType.slider:
        if (value is num && value.isFinite) {
          final min = field.min ?? 0;
          final max = field.max ?? 100;
          return value.clamp(min, max);
        }
        return null;
    }
  }
}

