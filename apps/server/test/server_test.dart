import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flow_core/flow_core.dart';
import 'package:http/http.dart' as http;
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  late HttpServer httpServer;
  late FlowStore store;
  late FlowServer flowServer;
  late String baseUrl;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('a2ui_server_test_');
    store = FlowStore(storagePath: '${tempDir.path}/flow.json');
    flowServer = FlowServer(
      store: store,
      streamDelay: const Duration(milliseconds: 25),
      enableLogging: false,
    );
    httpServer = await shelf_io.serve(
      flowServer.handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    baseUrl = 'http://127.0.0.1:${httpServer.port}';
  });

  tearDown(() async {
    flowServer.eventHub.dispose();
    await httpServer.close(force: true);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<List<Map<String, dynamic>>> readJsonlResponse(
    http.StreamedResponse response,
  ) async {
    final lines = await response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((l) => l.trim().isNotEmpty)
        .toList();
    return lines
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
  }

  group('Server Endpoints & Streaming', () {
    test('POST /a2ui/start streams createSurface and updateComponents unbuffered', () async {
      final client = http.Client();
      addTearDown(client.close);

      final req = http.Request('POST', Uri.parse('$baseUrl/a2ui/start'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({});

      final streamed = await client.send(req);
      expect(streamed.statusCode, equals(200));
      expect(
        streamed.headers['content-type'],
        contains('application/jsonl'),
      );

      final arrivalTimes = <int>[];
      final sw = Stopwatch()..start();
      final envelopes = <Map<String, dynamic>>[];

      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        arrivalTimes.add(sw.elapsedMilliseconds);
        envelopes.add(jsonDecode(line) as Map<String, dynamic>);
      }

      expect(envelopes.length, equals(2));
      expect(envelopes[0].containsKey('createSurface'), isTrue);
      expect(envelopes[1].containsKey('updateComponents'), isTrue);
      // Verify progressive streaming delay between message 0 and message 1
      expect(arrivalTimes[1] - arrivalTimes[0], greaterThanOrEqualTo(15));
    });

    test('POST /a2ui/action validates step and returns /formError on invalid email', () async {
      final client = http.Client();
      addTearDown(client.close);

      final req = http.Request('POST', Uri.parse('$baseUrl/a2ui/action'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'version': '1.0',
          'action': {
            'name': 'submit_step',
            'surfaceId': 'flow-step_profile-1',
            'sourceComponentId': 'step_step_profile_submit',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'context': {
              'stepId': 'step_profile',
              'flowVersion': 1,
            },
          },
          'metadata': {
            'a2uiRendererDataModel': {
              'version': '1.0',
              'surfaces': {
                'flow-step_profile-1': {
                  'answers': {
                    'full_name': 'Ada Lovelace',
                    'email': 'not-an-email',
                  },
                  'meta': {
                    'stepId': 'step_profile',
                    'flowVersion': 1,
                  },
                },
              },
            },
          },
        });

      final res = await client.send(req);
      final envelopes = await readJsonlResponse(res);

      expect(envelopes.length, equals(1));
      expect(envelopes.first.containsKey('updateDataModel'), isTrue);
      final update = envelopes.first['updateDataModel'] as Map<String, dynamic>;
      expect(update['path'], equals('/formError'));
      expect(update['value'], contains('geçerli bir e-posta'));
    });

    test('POST /a2ui/action advances to next step and then to summary screen', () async {
      final client = http.Client();
      addTearDown(client.close);

      // Step 1 valid submission -> advances to step_role
      final req1 = http.Request('POST', Uri.parse('$baseUrl/a2ui/action'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'version': '1.0',
          'action': {
            'name': 'submit_step',
            'surfaceId': 'flow-step_profile-1',
            'sourceComponentId': 'step_step_profile_submit',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'context': {
              'stepId': 'step_profile',
              'flowVersion': 1,
            },
          },
          'metadata': {
            'a2uiRendererDataModel': {
              'version': '1.0',
              'surfaces': {
                'flow-step_profile-1': {
                  'answers': {
                    'full_name': 'Ada Lovelace',
                    'email': 'ada@ornek.com',
                  },
                  'meta': {
                    'stepId': 'step_profile',
                    'flowVersion': 1,
                  },
                },
              },
            },
          },
        });

      final res1 = await client.send(req1);
      final envelopes1 = await readJsonlResponse(res1);
      expect(envelopes1.length, equals(3));
      expect(envelopes1[0]['deleteSurface']['surfaceId'], equals('flow-step_profile-1'));
      final createdSurface2 = envelopes1[1]['createSurface']['surfaceId'] as String;
      expect(createdSurface2, startsWith('flow-step_role-'));

      // Step 2 valid submission -> advances to summary
      final req2 = http.Request('POST', Uri.parse('$baseUrl/a2ui/action'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'version': '1.0',
          'action': {
            'name': 'submit_step',
            'surfaceId': createdSurface2,
            'sourceComponentId': 'step_step_role_submit',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'context': {
              'stepId': 'step_role',
              'flowVersion': 1,
            },
          },
          'metadata': {
            'a2uiRendererDataModel': {
              'version': '1.0',
              'surfaces': {
                createdSurface2: {
                  'answers': {
                    'full_name': 'Ada Lovelace',
                    'email': 'ada@ornek.com',
                    'role': ['developer'],
                  },
                  'meta': {
                    'stepId': 'step_role',
                    'flowVersion': 1,
                  },
                },
              },
            },
          },
        });

      final res2 = await client.send(req2);
      final envelopes2 = await readJsonlResponse(res2);
      expect(envelopes2.length, equals(3));
      final summarySurface = envelopes2[1]['createSurface']['surfaceId'] as String;
      expect(summarySurface, startsWith('flow-summary-'));
    });

    test('Publish rejects invalid draft with 422, accepts valid draft, increments version, and emits SSE', () async {
      final client = http.Client();
      addTearDown(client.close);

      // Connect SSE listener
      final sseReq = http.Request('GET', Uri.parse('$baseUrl/events'));
      final sseRes = await client.send(sseReq);
      final sseLines = <String>[];
      final sseSub = sseRes.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(sseLines.add);
      addTearDown(sseSub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sseLines.any((l) => l.contains('"version":1')), isTrue);

      // Save invalid draft (0 steps)
      final invalidDraft = const FlowDefinition(
        id: 'onboarding_flow',
        title: 'Bozuk Akış',
        steps: [],
      );
      final putInvalid = await client.put(
        Uri.parse('$baseUrl/flow/draft'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'draft': invalidDraft.toJson()}),
      );
      expect(putInvalid.statusCode, equals(200));

      // Publish must fail with 422
      final pubFail = await client.post(Uri.parse('$baseUrl/flow/publish'));
      expect(pubFail.statusCode, equals(422));

      // Save valid draft with "Yaşınızı girin" field added
      final template = createDefaultFlowTemplate();
      final step1WithAge = template.steps.first.copyWith(
        fields: [
          ...template.steps.first.fields,
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
      final validDraft = template.copyWith(
        steps: [step1WithAge, template.steps[1]],
      );

      await client.put(
        Uri.parse('$baseUrl/flow/draft'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'draft': validDraft.toJson()}),
      );

      final pubOk = await client.post(Uri.parse('$baseUrl/flow/publish'));
      expect(pubOk.statusCode, equals(200));
      final pubJson = jsonDecode(pubOk.body) as Map<String, dynamic>;
      expect(pubJson['publishedVersion'], equals(2));
      expect(pubJson['hasUnpublishedChanges'], isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sseLines.any((l) => l.contains('"version":2')), isTrue);

      // Now test /a2ui/refresh preserving full_name & email while adding age
      final refreshReq = http.Request('POST', Uri.parse('$baseUrl/a2ui/refresh'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'surfaceId': 'flow-step_profile-1',
          'stepId': 'step_profile',
          'metadata': {
            'a2uiRendererDataModel': {
              'version': '1.0',
              'surfaces': {
                'flow-step_profile-1': {
                  'answers': {
                    'full_name': 'Ada Lovelace',
                    'email': 'ada@ornek.com',
                  },
                  'meta': {
                    'stepId': 'step_profile',
                    'flowVersion': 1,
                  },
                },
              },
            },
          },
        });

      final refreshRes = await client.send(refreshReq);
      final refreshEnvelopes = await readJsonlResponse(refreshRes);
      expect(refreshEnvelopes.length, equals(3));

      final createDataModel = refreshEnvelopes[1]['createSurface']['dataModel']
          as Map<String, dynamic>;
      final reconciledAnswers =
          createDataModel['answers'] as Map<String, dynamic>;
      expect(reconciledAnswers['full_name'], equals('Ada Lovelace'));
      expect(reconciledAnswers['email'], equals('ada@ornek.com'));
      expect(reconciledAnswers['age'], equals(18)); // default min of slider
    });
  });

  group('Submission log (Gönderimler)', () {
    // Plays the role of the Player: echoes the server's data model back.
    Future<List<Map<String, dynamic>>> post(
      String path,
      Map<String, Object?> body,
    ) async {
      final client = http.Client();
      addTearDown(client.close);
      final req = http.Request('POST', Uri.parse('$baseUrl$path'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
      return readJsonlResponse(await client.send(req));
    }

    Map<String, dynamic> createdSurface(List<Map<String, dynamic>> envs) =>
        envs.firstWhere((e) => e.containsKey('createSurface'))['createSurface']
            as Map<String, dynamic>;

    Map<String, Object?> action(
      String name,
      Map<String, dynamic> surface,
      Map<String, Object?> answers,
    ) {
      final dm = surface['dataModel'] as Map<String, dynamic>;
      final meta = dm['meta'] as Map<String, dynamic>;
      return {
        'version': '1.0',
        'action': {
          'name': name,
          'surfaceId': surface['surfaceId'],
          'sourceComponentId': 'btn',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'context': {'stepId': meta['stepId'], 'flowVersion': meta['flowVersion']},
        },
        'metadata': {
          'a2uiRendererDataModel': {
            'surfaces': {
              surface['surfaceId']: {'answers': answers, 'meta': meta},
            },
          },
        },
      };
    }

    Future<List<dynamic>> sessions() async {
      final res = await http.get(Uri.parse('$baseUrl/sessions'));
      return (jsonDecode(res.body) as Map<String, dynamic>)['sessions']
          as List<dynamic>;
    }

    test('records start, rejected and accepted submits, then completion in one session', () async {
      final s1 = createdSurface(await post('/a2ui/start', {}));
      final sessionId =
          ((s1['dataModel'] as Map)['meta'] as Map)['sessionId'] as String;
      expect(sessionId, isNotEmpty);

      // Bad email -> rejected, still same surface.
      await post('/a2ui/action', action('submit_step', s1,
          {'full_name': 'Ada Lovelace', 'email': 'ada@'}));

      final s2 = createdSurface(await post('/a2ui/action', action('submit_step', s1,
          {'full_name': 'Ada Lovelace', 'email': 'ada@ornek.com'})));
      expect(((s2['dataModel'] as Map)['meta'] as Map)['sessionId'], sessionId);

      await post('/a2ui/action', action('submit_step', s2, {
        'full_name': 'Ada Lovelace',
        'email': 'ada@ornek.com',
        'role': ['developer'],
      }));

      final list = await sessions();
      expect(list, hasLength(1));
      final session = list.single as Map<String, dynamic>;
      expect(session['id'], sessionId);
      expect(session['status'], 'completed');
      final types = [
        for (final e in session['events'] as List) (e as Map)['type'],
      ];
      expect(types, ['start', 'rejected', 'submit', 'submit', 'completed']);
      expect((session['events'] as List)[1]['error'], contains('e-posta'));
      expect((session['latestAnswers'] as Map)['role'], ['developer']);
    });

    test('restart opens a new session and marks the unfinished one restarted', () async {
      final s1 = createdSurface(await post('/a2ui/start', {}));
      final first =
          ((s1['dataModel'] as Map)['meta'] as Map)['sessionId'] as String;

      // Player's restart icon: /a2ui/start with the current surface id.
      final s2 = createdSurface(
          await post('/a2ui/start', {'surfaceId': s1['surfaceId']}));
      final second =
          ((s2['dataModel'] as Map)['meta'] as Map)['sessionId'] as String;
      expect(second, isNot(first));
      expect((s2['dataModel'] as Map)['answers'],
          {'full_name': '', 'email': ''}); // starts from zero

      final byId = {
        for (final s in await sessions()) (s as Map)['id']: s['status'],
      };
      expect(byId[first], 'restarted');
      expect(byId[second], 'in_progress');
    });
  });

  group('Photo uploads (PhotoPicker)', () {
    test('POST /uploads stores the photo and GET returns the same bytes', () async {
      final bytes = List<int>.generate(64, (i) => i);
      final up = await http.post(
        Uri.parse('$baseUrl/uploads'),
        headers: {'Content-Type': 'image/png'},
        body: bytes,
      );
      expect(up.statusCode, 200);
      final path = (jsonDecode(up.body) as Map)['path'] as String;
      expect(isUploadedPhotoPath(path), isTrue);

      final down = await http.get(Uri.parse('$baseUrl$path'));
      expect(down.statusCode, 200);
      expect(down.headers['content-type'], 'image/png');
      expect(down.bodyBytes, bytes);
    });

    test('rejects non-image uploads and unknown or traversal names', () async {
      final bad = await http.post(
        Uri.parse('$baseUrl/uploads'),
        headers: {'Content-Type': 'text/plain'},
        body: 'hello',
      );
      expect(bad.statusCode, 400);

      final missing = await http.get(Uri.parse('$baseUrl/uploads/p_nope.jpg'));
      expect(missing.statusCode, 404);
      final traversal =
          await http.get(Uri.parse('$baseUrl/uploads/..%2Fflow.json'));
      expect(traversal.statusCode, 404);
    });

    test('server validation accepts uploaded paths and rejects foreign URLs', () {
      final step = FlowStep(
        id: 'step_photo',
        title: 'Fotoğraf',
        fields: const [
          FlowField(
            key: 'avatar',
            type: FieldType.photo,
            label: 'Profil fotoğrafı',
            required: true,
          ),
        ],
      );
      expect(
        FlowValidator.validateStepSubmission(step, {'avatar': ''}),
        isNotNull,
      );
      expect(
        FlowValidator.validateStepSubmission(
            step, {'avatar': 'https://evil.example/x.jpg'}),
        isNotNull,
      );
      expect(
        FlowValidator.validateStepSubmission(
            step, {'avatar': '/uploads/p_abc123.jpg'}),
        isNull,
      );
    });
  });
}
