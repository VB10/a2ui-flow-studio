import 'package:a2ui_core/a2ui_core.dart';

/// Sealed failure hierarchy for A2UI transport errors.
sealed class TransportFailure implements Exception {
  const TransportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class NetworkTransportFailure extends TransportFailure {
  const NetworkTransportFailure(super.message, {this.cause});

  final Object? cause;
}

final class StatusTransportFailure extends TransportFailure {
  const StatusTransportFailure({
    required this.statusCode,
    required String message,
    this.code,
  }) : super(message);

  final int statusCode;
  final String? code;
}

final class MalformedTransportFailure extends TransportFailure {
  const MalformedTransportFailure(super.message, {this.rawLine});

  final String? rawLine;
}

/// Event emitted over the Server-Sent Events (`/events`) stream.
class PublishedEvent {
  const PublishedEvent({required this.version});

  final int version;
}

/// Abstract transport contract between the Player and the A2UI Server.
abstract class A2uiTransport {
  /// Starts the flow (`POST /a2ui/start`), streaming A2UI message envelopes.
  Stream<Map<String, Object?>> start({String? previousSurfaceId});

  /// Sends a user-initiated action (`POST /a2ui/action`) along with the
  /// renderer's data model (`metadata.a2uiRendererDataModel`), streaming
  /// the resulting A2UI message envelopes.
  Stream<Map<String, Object?>> sendAction({
    required A2uiRendererAction action,
    required Map<String, Object?>? rendererDataModel,
  });

  /// Requests a live refresh (`POST /a2ui/refresh`) for the current step and
  /// data model after a new flow version is published.
  Stream<Map<String, Object?>> refresh({
    required String? surfaceId,
    required String? stepId,
    required Map<String, Object?>? rendererDataModel,
  });

  /// Subscribes to Server-Sent Events (`GET /events`) for live publish notifications.
  Stream<PublishedEvent> events();

  void dispose();
}

