import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/flow_catalog.dart';
import '../catalog/photo_uploader.dart';
import '../transport/a2ui_transport.dart';
import '../transport/http_jsonl_transport.dart';

/// Server URL configured via `--dart-define=SERVER_URL=http://localhost:8080`.
const String kDefaultServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://localhost:8080',
);

/// Provider for the active [A2uiTransport]. Override in tests with `FakeTransport`.
final a2uiTransportProvider = Provider<A2uiTransport>((ref) {
  final transport = HttpJsonlTransport(baseUrl: kDefaultServerUrl);
  ref.onDispose(transport.dispose);
  return transport;
});

/// Provider for photo picking + upload. Override in tests with a fake.
final photoUploaderProvider = Provider<PhotoUploader>(
  (ref) => HttpPhotoUploader(baseUrl: kDefaultServerUrl),
);

/// Sealed session state for the Player UI.
sealed class FlowSessionState {
  const FlowSessionState();
}

final class FlowSessionLoading extends FlowSessionState {
  const FlowSessionLoading();
}

final class FlowSessionReady extends FlowSessionState {
  const FlowSessionReady({
    required this.surface,
    this.isBusy = false,
    this.flowVersion,
    this.stepId,
    this.updatedBannerVersion,
  });

  final SurfaceModel<ComponentImplementation> surface;
  final bool isBusy;
  final int? flowVersion;
  final String? stepId;
  final int? updatedBannerVersion;

  FlowSessionReady copyWith({
    SurfaceModel<ComponentImplementation>? surface,
    bool? isBusy,
    int? flowVersion,
    String? stepId,
    int? updatedBannerVersion,
    bool clearBanner = false,
  }) =>
      FlowSessionReady(
        surface: surface ?? this.surface,
        isBusy: isBusy ?? this.isBusy,
        flowVersion: flowVersion ?? this.flowVersion,
        stepId: stepId ?? this.stepId,
        updatedBannerVersion:
            clearBanner ? null : (updatedBannerVersion ?? this.updatedBannerVersion),
      );
}

final class FlowSessionFailure extends FlowSessionState {
  const FlowSessionFailure({
    required this.failure,
    required this.retry,
  });

  final TransportFailure failure;
  final Future<void> Function() retry;
}

/// Riverpod Notifier managing the `MessageProcessor`, surface lifecycle,
/// action-to-transport bridge, single-request lock, and SSE live refresh.
class FlowSessionController extends AutoDisposeNotifier<FlowSessionState> {
  late MessageProcessor<ComponentImplementation> _processor;
  late A2uiTransport _transport;
  Subscription? _surfaceCreatedSub;
  Subscription? _surfaceDeletedSub;
  Subscription? _actionSub;
  StreamSubscription<PublishedEvent>? _sseSub;
  Timer? _bannerTimer;

  SurfaceModel<ComponentImplementation>? _activeSurface;
  bool _isRequestInFlight = false;
  int? _pendingRefreshVersion;

  MessageProcessor<ComponentImplementation> get processor => _processor;

  @override
  FlowSessionState build() {
    _transport = ref.watch(a2uiTransportProvider);
    _processor = MessageProcessor<ComponentImplementation>(
      // basic: steps without custom widgets. flow: basic + PhotoPicker.
      catalogs: [
        basicCatalog(),
        flowCatalog(uploader: ref.watch(photoUploaderProvider)),
      ],
      defaultVersion: A2uiProtocolVersion.v1_0,
      validationConfig: ValidationConfig.relaxed,
    );

    _surfaceCreatedSub = _processor.model.onSurfaceCreated.subscribe((surface) {
      _activeSurface = surface;
      _syncReadyState();
    });

    _surfaceDeletedSub = _processor.model.onSurfaceDeleted.subscribe((id) {
      if (_activeSurface?.id == id) {
        _activeSurface = _processor.model.allSurfaces.firstOrNull;
      }
    });

    _actionSub = _processor.model.onAction.subscribe(_onRendererAction);

    _sseSub = _transport.events().listen(_onPublishedEvent);

    ref.onDispose(() {
      _bannerTimer?.cancel();
      _sseSub?.cancel();
      _surfaceCreatedSub?.unsubscribe();
      _surfaceDeletedSub?.unsubscribe();
      _actionSub?.unsubscribe();
      _processor.dispose();
    });

    Future.microtask(startSession);
    return const FlowSessionLoading();
  }

  /// Starts or restarts the flow session.
  Future<void> startSession() async {
    if (_isRequestInFlight) return;
    _isRequestInFlight = true;
    state = const FlowSessionLoading();

    try {
      await _consumeStream(
        _transport.start(previousSurfaceId: _activeSurface?.id),
        isUserActivated: false,
      );
      _syncReadyState(isBusy: false);
    } on TransportFailure catch (failure) {
      state = FlowSessionFailure(
        failure: failure,
        retry: startSession,
      );
    } catch (e) {
      state = FlowSessionFailure(
        failure: NetworkTransportFailure('Beklenmeyen hata: $e', cause: e),
        retry: startSession,
      );
    } finally {
      _isRequestInFlight = false;
      _drainPendingRefresh();
    }
  }

  /// Manual or SSE-triggered live refresh.
  Future<void> refreshCurrentStep({int? newVersion}) async {
    if (_isRequestInFlight) {
      if (newVersion != null) {
        _pendingRefreshVersion = newVersion;
      }
      return;
    }

    final surface = _activeSurface;
    if (surface == null) {
      await startSession();
      return;
    }

    _isRequestInFlight = true;
    _syncReadyState(isBusy: true);

    final rendererDataModel = _processor.getRendererDataModel(
      version: A2uiProtocolVersion.v1_0,
    );
    final stepId = _readCurrentStepId(surface);

    try {
      await _consumeStream(
        _transport.refresh(
          surfaceId: surface.id,
          stepId: stepId,
          rendererDataModel: rendererDataModel,
        ),
        isUserActivated: false,
      );
      final updatedVer = newVersion ?? _readCurrentVersion(_activeSurface);
      _syncReadyState(
        isBusy: false,
        updatedBannerVersion: updatedVer,
      );
      if (updatedVer != null) {
        _scheduleBannerClear();
      }
    } on TransportFailure catch (failure) {
      state = FlowSessionFailure(
        failure: failure,
        retry: () => refreshCurrentStep(newVersion: newVersion),
      );
    } catch (e) {
      state = FlowSessionFailure(
        failure: NetworkTransportFailure('Yenileme hatası: $e', cause: e),
        retry: () => refreshCurrentStep(newVersion: newVersion),
      );
    } finally {
      _isRequestInFlight = false;
      _drainPendingRefresh();
    }
  }

  Future<void> _onRendererAction(A2uiRendererAction action) async {
    // Section 7 rule: Single-request lock while loading/refreshing
    if (_isRequestInFlight) return;

    _isRequestInFlight = true;
    _syncReadyState(isBusy: true);

    final rendererDataModel = _processor.getRendererDataModel(
      version: A2uiProtocolVersion.v1_0,
    );

    try {
      await _consumeStream(
        _transport.sendAction(
          action: action,
          rendererDataModel: rendererDataModel,
        ),
        isUserActivated: true,
      );
      _syncReadyState(isBusy: false);
    } on TransportFailure catch (failure) {
      state = FlowSessionFailure(
        failure: failure,
        retry: () async {
          _isRequestInFlight = false;
          await _onRendererAction(action);
        },
      );
    } catch (e) {
      state = FlowSessionFailure(
        failure: NetworkTransportFailure('Aksiyon hatası: $e', cause: e),
        retry: () async {
          _isRequestInFlight = false;
          await _onRendererAction(action);
        },
      );
    } finally {
      _isRequestInFlight = false;
      _drainPendingRefresh();
    }
  }

  void _onPublishedEvent(PublishedEvent event) {
    final currentVersion = _readCurrentVersion(_activeSurface);
    if (currentVersion != null && event.version != currentVersion) {
      unawaited(refreshCurrentStep(newVersion: event.version));
    }
  }

  void _drainPendingRefresh() {
    final pending = _pendingRefreshVersion;
    if (pending != null) {
      _pendingRefreshVersion = null;
      final currentVersion = _readCurrentVersion(_activeSurface);
      if (currentVersion != pending) {
        unawaited(refreshCurrentStep(newVersion: pending));
      }
    }
  }

  Future<void> _consumeStream(
    Stream<Map<String, Object?>> stream, {
    required bool isUserActivated,
  }) async {
    await for (final envelope in stream) {
      _processor.processMessages(
        envelope,
        isUserActivated: isUserActivated,
      );
      _syncReadyState(isBusy: true);
    }
  }

  void _syncReadyState({
    bool? isBusy,
    int? updatedBannerVersion,
  }) {
    final surface = _activeSurface;
    if (surface == null) return;

    final prev = state;
    final busy = isBusy ?? (prev is FlowSessionReady ? prev.isBusy : false);
    final bannerVer = updatedBannerVersion ??
        (prev is FlowSessionReady ? prev.updatedBannerVersion : null);

    state = FlowSessionReady(
      surface: surface,
      isBusy: busy,
      flowVersion: _readCurrentVersion(surface),
      stepId: _readCurrentStepId(surface),
      updatedBannerVersion: bannerVer,
    );
  }

  void _scheduleBannerClear() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      final current = state;
      if (current is FlowSessionReady) {
        state = current.copyWith(clearBanner: true);
      }
    });
  }

  int? _readCurrentVersion(SurfaceModel<ComponentImplementation>? surface) {
    if (surface == null) return null;
    final val = surface.dataModel.get('/meta/flowVersion');
    return (val as num?)?.toInt();
  }

  String? _readCurrentStepId(SurfaceModel<ComponentImplementation>? surface) {
    if (surface == null) return null;
    final val = surface.dataModel.get('/meta/stepId');
    return val as String?;
  }
}

final flowSessionProvider =
    AutoDisposeNotifierProvider<FlowSessionController, FlowSessionState>(
  FlowSessionController.new,
);

