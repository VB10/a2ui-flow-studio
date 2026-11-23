/// Studio-side read model of the server's `GET /sessions` payload.
enum StudioSessionStatus {
  inProgress('in_progress', 'Devam ediyor'),
  completed('completed', 'Tamamlandı'),
  restarted('restarted', 'Yeniden başladı');

  const StudioSessionStatus(this.jsonValue, this.label);
  final String jsonValue;
  final String label;

  static StudioSessionStatus fromJson(String? value) =>
      StudioSessionStatus.values.firstWhere(
        (s) => s.jsonValue == value,
        orElse: () => inProgress,
      );
}

enum StudioEventType {
  start('start', 'Başladı'),
  submit('submit', 'Gönderdi'),
  rejected('rejected', 'Hatalı deneme'),
  completed('completed', 'Akışı bitirdi');

  const StudioEventType(this.jsonValue, this.label);
  final String jsonValue;
  final String label;

  static StudioEventType fromJson(String? value) => StudioEventType.values
      .firstWhere((t) => t.jsonValue == value, orElse: () => submit);
}

class StudioSubmissionEvent {
  const StudioSubmissionEvent({
    required this.type,
    required this.at,
    required this.flowVersion,
    this.stepId,
    this.answers = const {},
    this.error,
  });

  final StudioEventType type;
  final DateTime at;
  final int flowVersion;
  final String? stepId;
  final Map<String, Object?> answers;
  final String? error;

  factory StudioSubmissionEvent.fromJson(Map<String, dynamic> json) =>
      StudioSubmissionEvent(
        type: StudioEventType.fromJson(json['type'] as String?),
        at: DateTime.tryParse(json['at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        flowVersion: (json['flowVersion'] as num?)?.toInt() ?? 0,
        stepId: json['stepId'] as String?,
        answers: (json['answers'] as Map?)?.cast<String, Object?>() ?? const {},
        error: json['error'] as String?,
      );
}

class StudioSession {
  const StudioSession({
    required this.id,
    required this.startedAt,
    required this.updatedAt,
    required this.status,
    required this.latestAnswers,
    required this.events,
  });

  final String id;
  final DateTime startedAt;
  final DateTime updatedAt;
  final StudioSessionStatus status;
  final Map<String, Object?> latestAnswers;
  final List<StudioSubmissionEvent> events;

  int get rejectedCount =>
      events.where((e) => e.type == StudioEventType.rejected).length;

  int get acceptedStepCount =>
      events.where((e) => e.type == StudioEventType.submit).length;

  factory StudioSession.fromJson(Map<String, dynamic> json) => StudioSession(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
        status: StudioSessionStatus.fromJson(json['status'] as String?),
        latestAnswers:
            (json['latestAnswers'] as Map?)?.cast<String, Object?>() ??
                const {},
        events: [
          for (final e in (json['events'] as List<dynamic>? ?? const []))
            StudioSubmissionEvent.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
}
