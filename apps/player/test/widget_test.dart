import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flow_core/flow_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/main.dart';

/// Fake transport backed by in-memory A2UI messages and an SSE controller.
class FakeTransport implements A2uiTransport {
  final StreamController<PublishedEvent> sseController =
      StreamController<PublishedEvent>.broadcast();

  bool failNextStart = false;
  A2uiRendererAction? lastSentAction;
  Map<String, Object?>? lastSentDataModel;
  Map<String, Object?>? lastRefreshDataModel;

  int currentVersion = 1;
  bool includeAgeFieldOnRefresh = false;

  @override
  Stream<Map<String, Object?>> start({String? previousSurfaceId}) async* {
    if (failNextStart) {
      failNextStart = false;
      throw const NetworkTransportFailure('Sunucu bağlantısı başarısız.');
    }

    yield {
      'version': '1.0',
      'createSurface': {
        'surfaceId': 'flow-step_profile-1',
        'catalogId':
            'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json',
        'sendDataModel': true,
        'dataModel': {
          'answers': {
            'full_name': '',
            'email': '',
          },
          'formError': '',
          'meta': {
            'stepId': 'step_profile',
            'flowVersion': 1,
          },
        },
      },
    };

    yield {
      'version': '1.0',
      'updateComponents': {
        'surfaceId': 'flow-step_profile-1',
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': [
              'step_title',
              'field_full_name',
              'field_email',
              'step_submit',
            ],
          },
          {
            'id': 'step_title',
            'component': 'Text',
            'text': '## Profil Bilgileri',
          },
          {
            'id': 'field_full_name',
            'component': 'TextField',
            'label': 'Ad Soyad',
            'value': {'@path': '/answers/full_name'},
          },
          {
            'id': 'field_email',
            'component': 'TextField',
            'label': 'E-posta Adresi',
            'value': {'@path': '/answers/email'},
          },
          {
            'id': 'step_submit_label',
            'component': 'Text',
            'text': 'Devam Et',
          },
          {
            'id': 'step_submit',
            'component': 'Button',
            'child': 'step_submit_label',
            'variant': 'primary',
            'action': {
              'event': {
                'name': 'submit_step',
                'context': {
                  'stepId': 'step_profile',
                  'flowVersion': 1,
                },
              },
            },
          },
        ],
      },
    };
  }

  @override
  Stream<Map<String, Object?>> sendAction({
    required A2uiRendererAction action,
    required Map<String, Object?>? rendererDataModel,
  }) async* {
    lastSentAction = action;
    lastSentDataModel = rendererDataModel;

    yield {
      'version': '1.0',
      'deleteSurface': {
        'surfaceId': action.surfaceId,
      },
    };
    yield {
      'version': '1.0',
      'createSurface': {
        'surfaceId': 'flow-summary-2',
        'catalogId':
            'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json',
        'sendDataModel': true,
        'dataModel': {
          'answers': {
            'full_name': 'Ada Lovelace',
            'email': 'ada@ornek.com',
          },
          'formError': '',
          'meta': {
            'stepId': AnswerReconciler.summaryStepId,
            'flowVersion': 1,
          },
        },
      },
    };
    yield {
      'version': '1.0',
      'updateComponents': {
        'surfaceId': 'flow-summary-2',
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['summary_title'],
          },
          {
            'id': 'summary_title',
            'component': 'Text',
            'text': '## Kayıt Tamamlandı',
          },
        ],
      },
    };
  }

  @override
  Stream<Map<String, Object?>> refresh({
    required String? surfaceId,
    required String? stepId,
    required Map<String, Object?>? rendererDataModel,
  }) async* {
    lastRefreshDataModel = rendererDataModel;
    final surfaces =
        (rendererDataModel?['surfaces'] as Map?)?.cast<String, Object?>() ?? {};
    final surfaceData = (surfaces[surfaceId] as Map?)?.cast<String, Object?>() ?? {};
    final existingAnswers =
        (surfaceData['answers'] as Map?)?.cast<String, Object?>() ?? {};

    if (surfaceId != null) {
      yield {
        'version': '1.0',
        'deleteSurface': {
          'surfaceId': surfaceId,
        },
      };
    }

    yield {
      'version': '1.0',
      'createSurface': {
        'surfaceId': 'flow-step_profile-2',
        'catalogId':
            'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json',
        'sendDataModel': true,
        'dataModel': {
          'answers': {
            ...existingAnswers,
            if (includeAgeFieldOnRefresh) 'age': 25,
          },
          'formError': '',
          'meta': {
            'stepId': 'step_profile',
            'flowVersion': currentVersion,
          },
        },
      },
    };

    yield {
      'version': '1.0',
      'updateComponents': {
        'surfaceId': 'flow-step_profile-2',
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': [
              'step_title',
              'field_full_name',
              'field_email',
              if (includeAgeFieldOnRefresh) 'field_age',
              'step_submit',
            ],
          },
          {
            'id': 'step_title',
            'component': 'Text',
            'text': '## Profil Bilgileri',
          },
          {
            'id': 'field_full_name',
            'component': 'TextField',
            'label': 'Ad Soyad',
            'value': {'@path': '/answers/full_name'},
          },
          {
            'id': 'field_email',
            'component': 'TextField',
            'label': 'E-posta Adresi',
            'value': {'@path': '/answers/email'},
          },
          if (includeAgeFieldOnRefresh)
            {
              'id': 'field_age',
              'component': 'Slider',
              'label': 'Yaşınızı girin',
              'min': 18,
              'max': 80,
              'value': {'@path': '/answers/age'},
            },
          {
            'id': 'step_submit_label',
            'component': 'Text',
            'text': 'Devam Et',
          },
          {
            'id': 'step_submit',
            'component': 'Button',
            'child': 'step_submit_label',
            'variant': 'primary',
            'action': {
              'event': {
                'name': 'submit_step',
                'context': {
                  'stepId': 'step_profile',
                  'flowVersion': currentVersion,
                },
              },
            },
          },
        ],
      },
    };
  }

  @override
  Stream<PublishedEvent> events() => sseController.stream;

  @override
  void dispose() {
    sseController.close();
  }
}

void main() {
  testWidgets(
    'Player renders surface, preserves typed values on SSE live refresh, and sends action payload',
    (tester) async {
      final fakeTransport = FakeTransport();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            a2uiTransportProvider.overrideWithValue(fakeTransport),
          ],
          child: const A2uiPlayerApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify initial step rendered
      expect(find.text('Profil Bilgileri'), findsOneWidget);
      expect(find.text('Ad Soyad'), findsOneWidget);
      expect(find.text('E-posta Adresi'), findsOneWidget);
      expect(find.text('v1'), findsOneWidget);

      // Type into Ad Soyad and E-posta Adresi fields
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      await tester.enterText(textFields.at(0), 'Ada Lovelace');
      await tester.enterText(textFields.at(1), 'ada@ornek.com');
      await tester.pump();

      // Simulate Studio publishing v2 with "Yaşınızı girin" Slider field
      fakeTransport.currentVersion = 2;
      fakeTransport.includeAgeFieldOnRefresh = true;
      fakeTransport.sseController.add(const PublishedEvent(version: 2));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify "updated to v2" banner and new field appear while typed values stay intact!
      expect(find.textContaining('updated to v2'), findsOneWidget);
      expect(find.text('Yaşınızı girin'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('ada@ornek.com'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);

      // Submit the step and verify action payload
      await tester.tap(find.text('Devam Et'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(fakeTransport.lastSentAction, isNotNull);
      expect(fakeTransport.lastSentAction!.name, equals('submit_step'));
      expect(find.text('Kayıt Tamamlandı'), findsOneWidget);
    },
  );

  testWidgets('Player shows failure state and retries when Tekrar Dene is pressed', (
    tester,
  ) async {
    final fakeTransport = FakeTransport()..failNextStart = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          a2uiTransportProvider.overrideWithValue(fakeTransport),
        ],
        child: const A2uiPlayerApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Bağlantı Hatası'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);

    // Retry succeeds
    await tester.tap(find.text('Tekrar Dene'));
    await tester.pumpAndSettle();

    expect(find.text('Profil Bilgileri'), findsOneWidget);
  });
}
