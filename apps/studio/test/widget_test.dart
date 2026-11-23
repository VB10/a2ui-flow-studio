import 'package:flow_core/flow_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio/main.dart';

class FakeStudioApiClient implements StudioApiClient {
  FakeStudioApiClient() {
    final template = createDefaultFlowTemplate();
    snapshot = FlowSnapshot(
      draft: template,
      published: template,
      publishedVersion: 1,
    );
  }

  late FlowSnapshot snapshot;
  int saveDraftCallCount = 0;
  int publishCallCount = 0;

  @override
  Future<FlowSnapshot> getFlow() async => snapshot;

  @override
  Future<FlowSnapshot> saveDraft(FlowDefinition draft) async {
    saveDraftCallCount++;
    snapshot = snapshot.copyWith(draft: draft);
    return snapshot;
  }

  @override
  Future<FlowSnapshot> publish() async {
    publishCallCount++;
    snapshot = FlowSnapshot(
      draft: snapshot.draft,
      published: snapshot.draft,
      publishedVersion: snapshot.publishedVersion + 1,
    );
    return snapshot;
  }

  @override
  Future<FlowSnapshot> reset() async {
    final template = createDefaultFlowTemplate();
    snapshot = FlowSnapshot(
      draft: template,
      published: template,
      publishedVersion: snapshot.publishedVersion + 1,
    );
    return snapshot;
  }

  @override
  Future<List<Map<String, Object?>>> previewStep(String? stepId) async {
    return [
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 'flow-${stepId ?? "step_profile"}-1',
        },
      },
    ];
  }

  @override
  Future<StudioAiEditResponse> aiEdit(String prompt) async {
    final step1 = snapshot.draft.steps.first;
    final updatedStep1 = step1.copyWith(
      fields: [
        ...step1.fields,
        const FlowField(
          key: 'age',
          type: FieldType.slider,
          label: 'Yaşınızı girin',
          required: true,
          min: 18,
          max: 80,
        ),
      ],
    );
    final updatedDraft = snapshot.draft.copyWith(
      steps: [updatedStep1, ...snapshot.draft.steps.skip(1)],
    );
    snapshot = snapshot.copyWith(draft: updatedDraft);
    return StudioAiEditResponse(
      snapshot: snapshot,
      summary: 'Yaşınızı girin alanı eklendi.',
      usedRemoteLlm: false,
    );
  }

  List<StudioSession> sessions = [];

  @override
  Future<List<StudioSession>> getSessions() async => sessions;

  @override
  Future<void> clearSessions() async => sessions = [];

  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'Studio controller & UI: add field, debounced draft save, reorder, and publish',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeApi = FakeStudioApiClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studioApiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const A2uiStudioApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify initial 3-column Studio loaded
      expect(find.text('A2UI Flow Studio'), findsOneWidget);
      expect(find.text('Published v1'), findsOneWidget);
      expect(find.text('Senkronize'), findsOneWidget);
      expect(find.text('Ad Soyad'), findsOneWidget);
      expect(find.text('E-posta Adresi'), findsOneWidget);

      // Click Quick Add "Yaşınızı girin"
      await tester.tap(find.byKey(const Key('quick_add_age_button')));
      await tester.pump();

      // Immediately shows "Unpublished changes" badge before debounce finishes
      expect(find.text('Unpublished changes'), findsOneWidget);
      expect(find.text('Yaşınızı girin'), findsOneWidget);

      // Wait for debounce timer (350ms) to flush draft to server
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(fakeApi.saveDraftCallCount, equals(1));
      expect(fakeApi.snapshot.draft.steps.first.fields.length, equals(3));

      // Click Publish button
      await tester.tap(find.byKey(const Key('publish_button')));
      await tester.pumpAndSettle();

      expect(fakeApi.publishCallCount, equals(1));
      expect(find.text('Published v2'), findsOneWidget);
      expect(find.text('Senkronize'), findsOneWidget);
    },
  );

  testWidgets(
    'Studio renders cleanly without overflow even on narrow (960px) window',
    (tester) async {
      tester.view.physicalSize = const Size(960, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeApi = FakeStudioApiClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studioApiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const A2uiStudioApp(),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('A2UI Flow Studio'), findsOneWidget);
      expect(find.text('Published v1'), findsOneWidget);
    },
  );

  testWidgets('Gönderimler tab lists Player sessions with rejected attempts', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeApi = FakeStudioApiClient()
      ..sessions = [
        StudioSession.fromJson({
          'id': 's_test_1',
          'startedAt': '2026-11-19T10:00:00Z',
          'updatedAt': '2026-11-19T10:01:00Z',
          'status': 'completed',
          'latestAnswers': {'full_name': 'Ada Lovelace'},
          'events': [
            {'type': 'start', 'at': '2026-11-19T10:00:00Z', 'flowVersion': 1, 'stepId': 'step_profile'},
            {'type': 'rejected', 'at': '2026-11-19T10:00:20Z', 'flowVersion': 1, 'stepId': 'step_profile',
             'answers': {'email': 'ada@'}, 'error': 'Geçerli bir e-posta girin.'},
            {'type': 'submit', 'at': '2026-11-19T10:00:30Z', 'flowVersion': 1, 'stepId': 'step_profile',
             'answers': {'full_name': 'Ada Lovelace'}},
            {'type': 'completed', 'at': '2026-11-19T10:01:00Z', 'flowVersion': 1},
          ],
        }),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [studioApiClientProvider.overrideWithValue(fakeApi)],
        child: const A2uiStudioApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submissions_tab')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Tamamlandı'), findsOneWidget);
    expect(find.textContaining('1 hatalı deneme'), findsOneWidget);

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Geçerli bir e-posta girin.'), findsOneWidget);

    // Leave the tab so the polling provider is disposed before teardown.
    await tester.tap(find.text('A2UI JSON'));
    await tester.pumpAndSettle();
    await tester.pump(kSessionsPollInterval);
  });
}
