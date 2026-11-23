import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lifecycle of one Player run through the flow.
enum SessionStatus {
  inProgress('in_progress'),
  completed('completed'),
  restarted('restarted');

  const SessionStatus(this.jsonValue);
  final String jsonValue;

  static SessionStatus fromJson(String? value) => SessionStatus.values
      .firstWhere((s) => s.jsonValue == value, orElse: () => inProgress);
}

/// Kind of a single recorded event inside a session.
enum SubmissionEventType {
  start('start'),
  submit('submit'),
  rejected('rejected'),
  completed('completed');

  const SubmissionEventType(this.jsonValue);
  final String jsonValue;

  static SubmissionEventType fromJson(String? value) =>
      SubmissionEventType.values
          .firstWhere((t) => t.jsonValue == value, orElse: () => submit);
}

class SubmissionEvent {
  SubmissionEvent({
    required this.type,
    required this.at,
    required this.flowVersion,
    this.stepId,
    this.answers = const {},
    this.error,
  });

  final SubmissionEventType type;
  final DateTime at;
  final int flowVersion;
  final String? stepId;
  final Map<String, Object?> answers;
  final String? error;

  factory SubmissionEvent.fromJson(Map<String, dynamic> json) =>
      SubmissionEvent(
        type: SubmissionEventType.fromJson(json['type'] as String?),
        at: DateTime.tryParse(json['at'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        flowVersion: (json['flowVersion'] as num?)?.toInt() ?? 0,
        stepId: json['stepId'] as String?,
        answers: (json['answers'] as Map?)?.cast<String, Object?>() ?? const {},
        error: json['error'] as String?,
      );

  Map<String, Object?> toJson() => {
        'type': type.jsonValue,
        'at': at.toIso8601String(),
        'flowVersion': flowVersion,
        if (stepId != null) 'stepId': stepId,
        if (answers.isNotEmpty) 'answers': answers,
        if (error != null) 'error': error,
      };
}

class FlowSession {
  FlowSession({
    required this.id,
    required this.startedAt,
    required this.updatedAt,
    required this.status,
    this.lastSurfaceId,
    List<SubmissionEvent>? events,
  }) : events = events ?? [];

  final String id;
  final DateTime startedAt;
  DateTime updatedAt;
  SessionStatus status;
  String? lastSurfaceId;
  final List<SubmissionEvent> events;

  /// Latest answers the Player sent in this session.
  Map<String, Object?> get latestAnswers {
    for (final e in events.reversed) {
      if (e.answers.isNotEmpty) return e.answers;
    }
    return const {};
  }

  factory FlowSession.fromJson(Map<String, dynamic> json) => FlowSession(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
        status: SessionStatus.fromJson(json['status'] as String?),
        lastSurfaceId: json['lastSurfaceId'] as String?,
        events: [
          for (final e in (json['events'] as List<dynamic>? ?? const []))
            SubmissionEvent.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'status': status.jsonValue,
        if (lastSurfaceId != null) 'lastSurfaceId': lastSurfaceId,
        'latestAnswers': latestAnswers,
        'events': events.map((e) => e.toJson()).toList(),
      };
}

/// Append-only log of what Players send while going through the flow.
///
/// The flow itself stays stateless: the session id travels in the surface
/// data model (`/meta/sessionId`). This log only *observes* submissions so
/// Studio can show them; nothing in the flow logic reads it back.
class SubmissionLog {
  SubmissionLog({String? storagePath, DateTime Function()? clock})
      : _storagePath = storagePath,
        _clock = clock ?? (() => DateTime.now().toUtc()) {
    _load();
  }

  final String? _storagePath;
  final DateTime Function() _clock;
  final Map<String, FlowSession> _sessions = {};
  final StreamController<FlowSession> _changes =
      StreamController<FlowSession>.broadcast();
  int _counter = 0;

  /// Emits a session every time it changes.
  Stream<FlowSession> get changes => _changes.stream;

  /// Sessions, newest activity first.
  List<FlowSession> get sessions => _sessions.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  FlowSession? sessionById(String id) => _sessions[id];

  /// Opens a new session. If [previousSurfaceId] belongs to an unfinished
  /// session, that session is marked [SessionStatus.restarted].
  String startSession({
    required int flowVersion,
    required String stepId,
    String? previousSurfaceId,
    String? previousSessionId,
  }) {
    final previous = previousSessionId != null
        ? _sessions[previousSessionId]
        : _sessionBySurface(previousSurfaceId);
    if (previous != null && previous.status == SessionStatus.inProgress) {
      previous
        ..status = SessionStatus.restarted
        ..updatedAt = _clock();
      _emit(previous);
    }

    final now = _clock();
    final id = 's_${now.millisecondsSinceEpoch.toRadixString(36)}_${++_counter}';
    final session = FlowSession(
      id: id,
      startedAt: now,
      updatedAt: now,
      status: SessionStatus.inProgress,
      events: [
        SubmissionEvent(
          type: SubmissionEventType.start,
          at: now,
          flowVersion: flowVersion,
          stepId: stepId,
        ),
      ],
    );
    _sessions[id] = session;
    _emit(session);
    return id;
  }

  /// Records a step submission. [error] set means the server rejected it.
  void recordSubmit({
    required String sessionId,
    required String stepId,
    required int flowVersion,
    required Map<String, Object?> answers,
    String? error,
  }) {
    final session = _sessions[sessionId];
    if (session == null) return;
    final now = _clock();
    session
      ..updatedAt = now
      ..events.add(SubmissionEvent(
        type: error == null
            ? SubmissionEventType.submit
            : SubmissionEventType.rejected,
        at: now,
        flowVersion: flowVersion,
        stepId: stepId,
        answers: Map<String, Object?>.from(answers),
        error: error,
      ));
    _emit(session);
  }

  void markCompleted({
    required String sessionId,
    required int flowVersion,
    required Map<String, Object?> answers,
  }) {
    final session = _sessions[sessionId];
    if (session == null) return;
    final now = _clock();
    session
      ..status = SessionStatus.completed
      ..updatedAt = now
      ..events.add(SubmissionEvent(
        type: SubmissionEventType.completed,
        at: now,
        flowVersion: flowVersion,
        answers: Map<String, Object?>.from(answers),
      ));
    _emit(session);
  }

  /// Remembers which surface the session is currently showing, so a later
  /// `/a2ui/start` carrying that surface id can close the session.
  void attachSurface(String sessionId, String surfaceId) {
    final session = _sessions[sessionId];
    if (session == null) return;
    session.lastSurfaceId = surfaceId;
    _persist();
  }

  void clear() {
    _sessions.clear();
    _persist();
  }

  Map<String, Object?> toJson() => {
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  void dispose() => _changes.close();

  FlowSession? _sessionBySurface(String? surfaceId) {
    if (surfaceId == null) return null;
    for (final s in _sessions.values) {
      if (s.lastSurfaceId == surfaceId) return s;
    }
    return null;
  }

  void _emit(FlowSession session) {
    _persist();
    if (!_changes.isClosed) _changes.add(session);
  }

  void _load() {
    final path = _storagePath;
    if (path == null) return;
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final raw in (json['sessions'] as List<dynamic>? ?? const [])) {
        final s = FlowSession.fromJson(Map<String, dynamic>.from(raw as Map));
        _sessions[s.id] = s;
      }
    } catch (e) {
      stderr.writeln('[SubmissionLog] Failed to load $path: $e');
    }
  }

  void _persist() {
    final path = _storagePath;
    if (path == null) return;
    try {
      final target = File(path);
      target.parent.createSync(recursive: true);
      final tmp = File('$path.tmp');
      tmp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(toJson()),
        flush: true,
      );
      tmp.renameSync(path);
    } catch (e) {
      stderr.writeln('[SubmissionLog] Atomic write failed for $path: $e');
    }
  }
}
