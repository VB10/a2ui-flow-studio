import 'package:a2ui_core/a2ui_core.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:flow_compiler/flow_compiler.dart';
import 'package:flow_core/flow_core.dart';
import 'package:test/test.dart';

void main() {
  const compiler = FlowCompiler();

  MessageProcessor<ComponentApi> createStrictProcessor() {
    final basic = BasicCatalog.v1_0();
    // Same shape as the Player's flow catalog: basic components + PhotoPicker.
    final flowCatalog = Catalog<ComponentApi, FunctionApi>(
      id: A2uiDsl.flowCatalogId,
      components: [
        ...basic.components.values,
        ComponentApi(
          name: 'PhotoPicker',
          schema: Schema.fromMap(FlowCatalogSchemas.photoPicker),
        ),
      ],
      functions: basic.functions.values.toList(),
      schemaId: basic.schemaId,
      protocolVersion: basic.protocolVersion,
      definitions: basic.definitions,
    );
    return MessageProcessor.forAgent(
      catalogs: [basic, flowCatalog],
      defaultVersion: A2uiProtocolVersion.v1_0,
      validationConfig: ValidationConfig.strict,
    );
  }

  group('FlowCompiler strict A2UI validation', () {
    for (final fieldType in FieldType.values) {
      for (final isRequired in [false, true]) {
        test(
          'compiles ${fieldType.jsonValue} (required: $isRequired) and passes ValidationConfig.strict',
          () {
            final field = FlowField(
              key: 'test_${fieldType.jsonValue}',
              type: fieldType,
              label: 'Test ${fieldType.displayName}',
              placeholder: 'Test ipucu',
              required: isRequired,
              min: fieldType.hasMinMax ? 10 : null,
              max: fieldType.hasMinMax ? 90 : null,
              minLength: fieldType == FieldType.text ? 3 : null,
              options: fieldType.isChoice
                  ? const [
                      FieldOption(value: 'opt_a', label: 'Seçenek A'),
                      FieldOption(value: 'opt_b', label: 'Seçenek B'),
                    ]
                  : null,
            );

            final step = FlowStep(
              id: 'step_single',
              title: 'Tek Alan Testi',
              description: 'Açıklama metni',
              fields: [field],
            );

            final flow = FlowDefinition(
              id: 'test_flow',
              title: 'Test Akışı',
              steps: [step],
            );

            final payload = compiler.compileStep(
              flow: flow,
              step: step,
              flowVersion: 1,
              nonce: 1,
            );

            final processor = createStrictProcessor();
            expect(
              () => processor.processMessages(payload.messages),
              returnsNormally,
            );

            final surface = processor.model.getSurface(payload.surfaceId);
            expect(surface, isNotNull);
            expect(surface!.sendDataModel, isTrue);
          },
        );
      }
    }

    test('handles 0, 1, and 2+ required fields without violating and(minItems: 2)', () {
      // 0 required fields
      const step0 = FlowStep(
        id: 's0',
        title: 'Sıfır Zorunlu',
        fields: [
          FlowField(
            key: 'opt_text',
            type: FieldType.text,
            label: 'Opsiyonel Metin',
            required: false,
          ),
        ],
      );

      // 1 required field (single condition -> must NOT wrap in `and`)
      const step1 = FlowStep(
        id: 's1',
        title: 'Tek Zorunlu',
        fields: [
          FlowField(
            key: 'req_role',
            type: FieldType.singleChoice,
            label: 'Zorunlu Rol',
            required: true,
            options: [
              FieldOption(value: 'a', label: 'A'),
              FieldOption(value: 'b', label: 'B'),
            ],
          ),
        ],
      );

      // 2+ required fields (wraps in `and` with >=2 conditions)
      const step2 = FlowStep(
        id: 's2',
        title: 'Çoklu Zorunlu',
        fields: [
          FlowField(
            key: 'req_name',
            type: FieldType.text,
            label: 'Ad',
            required: true,
            minLength: 2,
          ),
          FlowField(
            key: 'req_email',
            type: FieldType.email,
            label: 'E-posta',
            required: true,
          ),
        ],
      );

      const flow = FlowDefinition(
        id: 'edge_flow',
        title: 'Kenar Durumları',
        steps: [step0, step1, step2],
      );

      final processor = createStrictProcessor();

      final p0 = compiler.compileStep(
        flow: flow,
        step: step0,
        flowVersion: 1,
        nonce: 1,
      );
      expect(() => processor.processMessages(p0.messages), returnsNormally);

      final p1 = compiler.compileStep(
        flow: flow,
        step: step1,
        flowVersion: 1,
        nonce: 2,
        previousSurfaceId: p0.surfaceId,
      );
      expect(() => processor.processMessages(p1.messages), returnsNormally);

      final p2 = compiler.compileStep(
        flow: flow,
        step: step2,
        flowVersion: 1,
        nonce: 3,
        previousSurfaceId: p1.surfaceId,
      );
      expect(() => processor.processMessages(p2.messages), returnsNormally);
    });

    test('compiles default template steps and summary screen cleanly under strict mode', () {
      final flow = createDefaultFlowTemplate();
      final processor = createStrictProcessor();

      final firstStepPayload = compiler.compileStep(
        flow: flow,
        step: flow.steps[0],
        flowVersion: 1,
        nonce: 10,
      );
      expect(
        () => processor.processMessages(firstStepPayload.messages),
        returnsNormally,
      );

      final secondStepPayload = compiler.compileStep(
        flow: flow,
        step: flow.steps[1],
        flowVersion: 1,
        nonce: 11,
        previousSurfaceId: firstStepPayload.surfaceId,
        existingAnswers: {
          'full_name': 'Ada Lovelace',
          'email': 'ada@ornek.com',
        },
      );
      expect(
        () => processor.processMessages(secondStepPayload.messages),
        returnsNormally,
      );
      expect(processor.model.getSurface(firstStepPayload.surfaceId), isNull);
      expect(
        processor.model.getSurface(secondStepPayload.surfaceId),
        isNotNull,
      );

      final summaryPayload = compiler.compileSummary(
        flow: flow,
        flowVersion: 1,
        nonce: 12,
        previousSurfaceId: secondStepPayload.surfaceId,
        answers: {
          'full_name': 'Ada Lovelace',
          'email': 'ada@ornek.com',
          'role': ['developer'],
        },
      );
      expect(
        () => processor.processMessages(summaryPayload.messages),
        returnsNormally,
      );
      expect(processor.model.getSurface(summaryPayload.surfaceId), isNotNull);
    });
  });

  test('photo step uses the flow catalog, other steps stay on basic', () {
    FlowStep stepWith(FieldType type) => FlowStep(
          id: 'step_${type.jsonValue}',
          title: 'T',
          fields: [FlowField(key: 'k', type: type, label: 'L')],
        );
    String catalogOf(FlowStep step) {
      final payload = compiler.compileStep(
        flow: FlowDefinition(id: 'f', title: 'F', steps: [step]),
        step: step,
        flowVersion: 1,
        nonce: 1,
      );
      final create = payload.messages
          .firstWhere((m) => m.containsKey('createSurface'))['createSurface']
          as Map;
      return create['catalogId'] as String;
    }

    expect(catalogOf(stepWith(FieldType.photo)), A2uiDsl.flowCatalogId);
    expect(catalogOf(stepWith(FieldType.text)), A2uiDsl.basicCatalogId);
  });
}
