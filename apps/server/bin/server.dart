import 'dart:io';

import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final delayMs =
      int.tryParse(Platform.environment['STREAM_DELAY_MS'] ?? '120') ?? 120;
  final storagePath =
      Platform.environment['FLOW_STORAGE_PATH'] ?? 'apps/server/data/flow.json';

  final submissionsPath = Platform.environment['SUBMISSIONS_PATH'] ??
      'apps/server/data/submissions.json';

  final uploadsDir =
      Platform.environment['UPLOADS_DIR'] ?? 'apps/server/data/uploads';

  final store = FlowStore(storagePath: storagePath);
  final flowServer = FlowServer(
    store: store,
    submissionLog: SubmissionLog(storagePath: submissionsPath),
    uploadStore: UploadStore(directory: uploadsDir),
    streamDelay: Duration(milliseconds: delayMs),
  );

  final httpServer = await shelf_io.serve(
    flowServer.handler,
    InternetAddress.anyIPv4,
    port,
  );

  print('══════════════════════════════════════════════════════════════');
  print(' A2UI Flow Studio Server aktif!');
  print(' Adres:            http://${httpServer.address.host}:${httpServer.port}');
  print(' Kayıt dosyası:    $storagePath');
  print(' Gönderimler:      $submissionsPath (GET /sessions)');
  print(' Fotoğraflar:      $uploadsDir (POST /uploads)');
  print(' Yayın sürümü:     v${store.snapshot.publishedVersion}');
  print(' Stream gecikmesi: ${delayMs}ms (JSONL progressive render)');
  print('══════════════════════════════════════════════════════════════');
}

