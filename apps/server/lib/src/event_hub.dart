import 'dart:async';
import 'dart:convert';

/// Broadcasts Server-Sent Events (SSE) to connected Player instances.
class EventHub {
  final Set<StreamController<List<int>>> _clients = {};

  int get clientCount => _clients.length;

  /// Creates a new SSE byte stream for a connecting client and immediately
  /// emits an initial `connected` / current `published` version event so the
  /// client can reconcile its version upon reconnecting.
  Stream<List<int>> subscribe({required int currentPublishedVersion}) {
    late final StreamController<List<int>> controller;
    Timer? keepAliveTimer;

    void cleanup() {
      keepAliveTimer?.cancel();
      _clients.remove(controller);
      if (!controller.isClosed) {
        controller.close();
      }
    }

    controller = StreamController<List<int>>(
      onCancel: cleanup,
    );

    _clients.add(controller);

    // Send initial state immediately so reconnecting clients can check version
    _sendSseFrame(
      controller,
      event: 'published',
      data: {'version': currentPublishedVersion},
    );

    keepAliveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!controller.isClosed) {
        controller.add(utf8.encode(': keepalive\n\n'));
      }
    });

    return controller.stream;
  }

  /// Broadcasts a `published` SSE event with the new [version] to all listeners.
  void broadcastPublished(int version) {
    final deadClients = <StreamController<List<int>>>[];
    for (final client in _clients) {
      if (client.isClosed) {
        deadClients.add(client);
        continue;
      }
      try {
        _sendSseFrame(
          client,
          event: 'published',
          data: {'version': version},
        );
      } catch (_) {
        deadClients.add(client);
      }
    }
    for (final dead in deadClients) {
      _clients.remove(dead);
    }
  }

  /// Broadcasts an arbitrary SSE [event] with JSON [data] to all listeners.
  void broadcast(String event, Map<String, Object?> data) {
    final deadClients = <StreamController<List<int>>>[];
    for (final client in _clients) {
      if (client.isClosed) {
        deadClients.add(client);
        continue;
      }
      try {
        _sendSseFrame(client, event: event, data: data);
      } catch (_) {
        deadClients.add(client);
      }
    }
    _clients.removeAll(deadClients);
  }

  void _sendSseFrame(
    StreamController<List<int>> controller, {
    required String event,
    required Map<String, Object?> data,
  }) {
    final payload = 'event: $event\ndata: ${jsonEncode(data)}\n\n';
    controller.add(utf8.encode(payload));
  }

  void dispose() {
    for (final client in _clients.toList()) {
      client.close();
    }
    _clients.clear();
  }
}

