import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/flow_editor_controller.dart';
import 'submission_models.dart';

/// How often the "Gönderimler" tab asks the server for sessions.
const Duration kSessionsPollInterval = Duration(seconds: 2);

/// Polls `GET /sessions` while the tab is visible (autoDispose stops it
/// when the tab is closed). Polling instead of SSE because the web `http`
/// client buffers streamed responses.
final sessionsProvider =
    StreamProvider.autoDispose<List<StudioSession>>((ref) async* {
  final api = ref.watch(studioApiClientProvider);
  while (true) {
    yield await api.getSessions();
    await Future<void>.delayed(kSessionsPollInterval);
  }
});
