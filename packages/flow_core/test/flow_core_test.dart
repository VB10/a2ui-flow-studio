import 'dart:convert';

import 'package:flow_core/flow_core.dart';
import 'package:test/test.dart';

void main() {
  group('FlowDefinition JSON round-trip', () {
    test('serializes and deserializes default template identically', () {
      final template = createDefaultFlowTemplate();
      final jsonStr = jsonEncode(template.toJson());
      final decoded = FlowDefinition.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      expect(decoded, equals(template));
      expect(decoded.steps.length, equals(2));
      expect(decoded.steps.first.fields.length, equals(2));
    });

    test('FlowSnapshot tracks hasUnpublishedChanges accurately', () {
      final template = createDefaultFlowTemplate();
      final snapshot = FlowSnapshot(
        draft: template,
        published: template,
        publishedVersion: 1,
      );
      expect(snapshot.hasUnpublishedChanges, isFalse);

      final modifiedDraft = template.copyWith(title: 'Yeni Başlık');
      final dirtySnapshot = snapshot.copyWith(draft: modifiedDraft);
      expect(dirtySnapshot.hasUnpublishedChanges, isTrue);
    });
  });

  group('FlowValidator', () {
    test('default template passes validation', () {
      final issues = FlowValidator.validateFlow(createDefaultFlowTemplate());
      expect(issues, isEmpty);
    });

    test('rejects flow with no steps', () {
      const flow = FlowDefinition(id: 'f1', title: 'Test', steps: []);
      final issues = FlowValidator.validateFlow(flow);
      expect(issues.map((i) => i.code), contains('no_steps'));
    });

    test('rejects duplicate step ids and field keys', () {
      const flow = FlowDefinition(
        id: 'f1',
        title: 'Test',
        steps: [
          FlowStep(
            id: 'step_1',
            title: 'Adım 1',
            fields: [
              FlowField(key: 'name', type: FieldType.text, label: 'Ad'),
            ],
          ),
          FlowStep(
            id: 'step_1',
            title: 'Adım 2',
            fields: [
              FlowField(key: 'name', type: FieldType.email, label: 'E-posta'),
            ],
          ),
        ],
      );
      final issues = FlowValidator.validateFlow(flow);
      final codes = issues.map((i) => i.code).toList();
      expect(codes, contains('duplicate_step_id'));
      expect(codes, contains('duplicate_field_key'));
    });

    test('rejects choice fields with fewer than 2 options', () {
      const flow = FlowDefinition(
        id: 'f1',
        title: 'Test',
        steps: [
          FlowStep(
            id: 'step_1',
            title: 'Adım 1',
            fields: [
              FlowField(
                key: 'role',
                type: FieldType.singleChoice,
                label: 'Rol',
                options: [FieldOption(value: 'dev', label: 'Developer')],
              ),
            ],
          ),
        ],
      );
      final issues = FlowValidator.validateFlow(flow);
      expect(issues.map((i) => i.code), contains('insufficient_options'));
    });

    test('rejects slider without max or with min >= max', () {
      const flow = FlowDefinition(
        id: 'f1',
        title: 'Test',
        steps: [
          FlowStep(
            id: 'step_1',
            title: 'Adım 1',
            fields: [
              FlowField(
                key: 'age',
                type: FieldType.slider,
                label: 'Yaş',
                min: 50,
                max: 20,
              ),
              FlowField(
                key: 'score',
                type: FieldType.slider,
                label: 'Skor',
              ),
            ],
          ),
        ],
      );
      final issues = FlowValidator.validateFlow(flow);
      final codes = issues.map((i) => i.code).toList();
      expect(codes, contains('slider_invalid_range'));
      expect(codes, contains('slider_missing_max'));
    });

    test('rejects unknown next step and cycles', () {
      const flowWithCycle = FlowDefinition(
        id: 'f1',
        title: 'Test',
        steps: [
          FlowStep(
            id: 's1',
            title: 'Adım 1',
            fields: [],
            next: StepNext(defaultStepId: 's2'),
          ),
          FlowStep(
            id: 's2',
            title: 'Adım 2',
            fields: [],
            next: StepNext(defaultStepId: 's1'),
          ),
        ],
      );
      final issues = FlowValidator.validateFlow(flowWithCycle);
      expect(issues.map((i) => i.code), contains('step_cycle_detected'));
    });
  });

  group('AnswerReconciler (Section 7 rules)', () {
    final baseFlow = createDefaultFlowTemplate();

    test('1. Field added -> new field omitted/empty, existing answers kept', () {
      final updatedStep1 = baseFlow.steps.first.copyWith(
        fields: [
          ...baseFlow.steps.first.fields,
          const FlowField(
            key: 'age',
            type: FieldType.slider,
            label: 'Yaşınız',
            min: 18,
            max: 80,
          ),
        ],
      );
      final updatedFlow = baseFlow.copyWith(
        steps: [updatedStep1, baseFlow.steps[1]],
      );

      final result = AnswerReconciler.reconcile(
        newFlow: updatedFlow,
        currentStepId: 'step_profile',
        currentAnswers: {
          'full_name': 'Ada Lovelace',
          'email': 'ada@analytical.engine',
        },
      );

      expect(result.targetStepId, equals('step_profile'));
      expect(result.answers['full_name'], equals('Ada Lovelace'));
      expect(result.answers['email'], equals('ada@analytical.engine'));
      expect(result.answers.containsKey('age'), isFalse);
    });

    test('2. Field deleted -> answer removed from data model', () {
      final updatedStep1 = baseFlow.steps.first.copyWith(
        fields: [baseFlow.steps.first.fields.first], // email removed
      );
      final updatedFlow = baseFlow.copyWith(
        steps: [updatedStep1, baseFlow.steps[1]],
      );

      final result = AnswerReconciler.reconcile(
        newFlow: updatedFlow,
        currentStepId: 'step_profile',
        currentAnswers: {
          'full_name': 'Ada Lovelace',
          'email': 'ada@analytical.engine',
        },
      );

      expect(result.answers['full_name'], equals('Ada Lovelace'));
      expect(result.answers.containsKey('email'), isFalse);
    });

    test('3. Label or placeholder changed -> answer preserved', () {
      final updatedField = baseFlow.steps.first.fields.first.copyWith(
        label: 'Tam Adınız',
        placeholder: 'Yeni ipucu',
      );
      final updatedStep1 = baseFlow.steps.first.copyWith(
        fields: [updatedField, baseFlow.steps.first.fields[1]],
      );
      final updatedFlow = baseFlow.copyWith(
        steps: [updatedStep1, baseFlow.steps[1]],
      );

      final result = AnswerReconciler.reconcile(
        newFlow: updatedFlow,
        currentStepId: 'step_profile',
        currentAnswers: {'full_name': 'Ada Lovelace'},
      );

      expect(result.answers['full_name'], equals('Ada Lovelace'));
    });

    test('4. Field type changed to incompatible type -> answer dropped', () {
      final changedTypeField = baseFlow.steps.first.fields.first.copyWith(
        type: FieldType.checkbox,
      );
      final updatedStep1 = baseFlow.steps.first.copyWith(
        fields: [changedTypeField, baseFlow.steps.first.fields[1]],
      );
      final updatedFlow = baseFlow.copyWith(
        steps: [updatedStep1, baseFlow.steps[1]],
      );

      final result = AnswerReconciler.reconcile(
        newFlow: updatedFlow,
        currentStepId: 'step_profile',
        currentAnswers: {'full_name': 'Ada Lovelace'},
      );

      expect(result.answers.containsKey('full_name'), isFalse);
    });

    test('5. Choice option deleted -> deleted value removed from answer list', () {
      final roleField = baseFlow.steps[1].fields.first;
      final reducedOptions = roleField.options!
          .where((o) => o.value != 'developer')
          .toList();
      final updatedStep2 = baseFlow.steps[1].copyWith(
        fields: [roleField.copyWith(options: reducedOptions)],
      );
      final updatedFlow = baseFlow.copyWith(
        steps: [baseFlow.steps.first, updatedStep2],
      );

      final result = AnswerReconciler.reconcile(
        newFlow: updatedFlow,
        currentStepId: 'step_role',
        currentAnswers: {
          'role': ['developer'],
        },
      );

      expect(result.answers['role'], isEmpty);
    });

    test('6. Current step deleted -> returns to first step, keeps matching answers', () {
      final singleStepFlow = baseFlow.copyWith(
        steps: [baseFlow.steps.first.copyWith(next: const StepNext())],
      );

      final result = AnswerReconciler.reconcile(
        newFlow: singleStepFlow,
        currentStepId: 'step_role',
        currentAnswers: {
          'full_name': 'Ada Lovelace',
          'role': ['developer'],
        },
      );

      expect(result.targetStepId, equals('step_profile'));
      expect(result.isSummary, isFalse);
      expect(result.answers['full_name'], equals('Ada Lovelace'));
      expect(result.answers.containsKey('role'), isFalse);
    });

    test('7. User on summary screen -> stays on summary with reconciled answers', () {
      final result = AnswerReconciler.reconcile(
        newFlow: baseFlow,
        currentStepId: AnswerReconciler.summaryStepId,
        currentAnswers: {
          'full_name': 'Ada Lovelace',
          'deleted_key': 'eski',
        },
      );

      expect(result.isSummary, isTrue);
      expect(result.targetStepId, isNull);
      expect(result.answers['full_name'], equals('Ada Lovelace'));
      expect(result.answers.containsKey('deleted_key'), isFalse);
    });
  });
}

