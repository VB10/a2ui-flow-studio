import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flow_compiler/flow_compiler.dart';
import 'package:flow_core/flow_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/main.dart';

/// Serves the real compiler output for a one-step flow with a photo field.
class PhotoStepTransport implements A2uiTransport {
  Map<String, Object?>? lastSentDataModel;
  A2uiRendererAction? lastSentAction;

  static final _step = FlowStep(
    id: 'step_photo',
    title: 'Profil Fotoğrafı',
    fields: const [
      FlowField(
        key: 'avatar',
        type: FieldType.photo,
        label: 'Profil fotoğrafın',
        required: true,
      ),
    ],
  );

  @override
  Stream<Map<String, Object?>> start({String? previousSurfaceId}) =>
      Stream.fromIterable(const FlowCompiler()
          .compileStep(
            flow: FlowDefinition(id: 'f', title: 'Foto', steps: [_step]),
            step: _step,
            flowVersion: 1,
            nonce: 1,
          )
          .messages);

  @override
  Stream<Map<String, Object?>> sendAction({
    required A2uiRendererAction action,
    required Map<String, Object?>? rendererDataModel,
  }) {
    lastSentAction = action;
    lastSentDataModel = rendererDataModel;
    return const Stream.empty();
  }

  @override
  Stream<Map<String, Object?>> refresh({
    required String? surfaceId,
    required String? stepId,
    required Map<String, Object?>? rendererDataModel,
  }) =>
      const Stream.empty();

  @override
  Stream<PublishedEvent> events() => const Stream.empty();

  @override
  void dispose() {}
}

class FakeUploader implements PhotoUploader {
  int calls = 0;

  @override
  Future<String?> pickAndUpload() async {
    calls++;
    return '/uploads/p_test123.jpg';
  }

  @override
  String resolve(String path) => 'http://localhost$path';
}

void main() {
  testWidgets(
    'PhotoPicker from the flow catalog writes the uploaded path and the '
    'submit action carries it to the server',
    (tester) async {
      final transport = PhotoStepTransport();
      final uploader = FakeUploader();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            a2uiTransportProvider.overrideWithValue(transport),
            photoUploaderProvider.overrideWithValue(uploader),
          ],
          child: const A2uiPlayerApp(),
        ),
      );
      await tester.pumpAndSettle();

      // The server asked for our custom component; the Player drew it.
      expect(find.byType(PhotoPickerField), findsOneWidget);
      expect(find.text('Profil fotoğrafın'), findsOneWidget);
      expect(find.text('Fotoğraf seç'), findsOneWidget);

      // Required photo: the submit button stays disabled until one is picked.
      final submit = find.widgetWithText(FilledButton, 'Devam Et');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('photo_picker_tap')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(uploader.calls, 1);
      expect(find.text('Fotoğrafı değiştir'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

      await tester.tap(submit);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(transport.lastSentAction?.name, 'submit_step');
      final surfaces = (transport.lastSentDataModel?['surfaces'] as Map?)
          ?.values
          .cast<Map>();
      final answers = surfaces?.first['answers'] as Map?;
      expect(answers?['avatar'], '/uploads/p_test123.jpg');
    },
  );
}
