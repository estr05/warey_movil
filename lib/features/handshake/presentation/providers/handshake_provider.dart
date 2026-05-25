// lib/features/handshake/presentation/providers/handshake_provider.dart
//
// Feature: Handshake - Capa Presentation (Gestion de Estado)
// Controla el ciclo de vida UX del pairing. No valida seguridad localmente.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/handshake_repository_impl.dart';
import '../../domain/repositories/handshake_repository.dart';
import '../../../../core/services/device_uuid_service.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/services/background_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../tracking/data/repositories/safe_place_repository.dart';
import '../../../tracking/domain/services/geofence_service.dart';

// Definicion de estados

sealed class HandshakeState {
  final PairingLifecycleStatus visualStatus;
  const HandshakeState(this.visualStatus);

  DateTime? get cooldownUntil => null;
}

final class HandshakeIdle extends HandshakeState {
  const HandshakeIdle() : super(PairingLifecycleStatus.pending);
}

final class HandshakeLoading extends HandshakeState {
  final String message;
  const HandshakeLoading([this.message = 'Validando codigo...'])
    : super(PairingLifecycleStatus.pending);
}

final class Success extends HandshakeState {
  final PairedDeviceInfo device;
  Success(this.device) : super(device.status);
}

final class HandshakeConfirmationRequired extends HandshakeState {
  final PairingConflict conflict;
  const HandshakeConfirmationRequired(this.conflict)
    : super(PairingLifecycleStatus.pending);
}

final class HandshakeCodeExpiredState extends HandshakeState {
  final String message;
  @override
  final DateTime? cooldownUntil;

  const HandshakeCodeExpiredState({
    required this.message,
    required this.cooldownUntil,
  }) : super(PairingLifecycleStatus.pending);
}

final class HandshakeRevokedState extends HandshakeState {
  final String message;
  const HandshakeRevokedState(this.message)
    : super(PairingLifecycleStatus.revoked);
}

final class HandshakeCooldown extends HandshakeState {
  final String message;
  @override
  final DateTime cooldownUntil;

  const HandshakeCooldown({required this.message, required this.cooldownUntil})
    : super(PairingLifecycleStatus.pending);
}

final class HandshakeError extends HandshakeState {
  final String message;
  @override
  final DateTime? cooldownUntil;

  const HandshakeError({
    required this.message,
    required PairingLifecycleStatus visualStatus,
    this.cooldownUntil,
  }) : super(visualStatus);
}

// Notifier

class HandshakeNotifier extends StateNotifier<HandshakeState> {
  final HandshakeRepository _repository;
  final DeviceUuidService _deviceUuidService;
  final Ref _ref;

  String? _lastPairingCode;
  DeviceFingerprint? _lastFingerprint;
  DateTime? _cooldownUntil;

  HandshakeNotifier({
    required HandshakeRepository repository,
    required DeviceUuidService deviceUuidService,
    required Ref ref,
  }) : _repository = repository,
       _deviceUuidService = deviceUuidService,
       _ref = ref,
       super(const HandshakeIdle());

  Future<void> validatePairingCode(String pairingCode) async {
    await _runHandshake(pairingCode.trim(), confirmReplacement: false);
  }

  Future<void> confirmReplacement() async {
    final code = _lastPairingCode;
    if (code == null || code.isEmpty) {
      state = HandshakeError(
        message: 'No hay codigo pendiente para confirmar.',
        visualStatus: PairingLifecycleStatus.pending,
        cooldownUntil: _startCooldown(const Duration(seconds: 2)),
      );
      return;
    }

    await _runHandshake(code, confirmReplacement: true);
  }

  Future<void> continueToDashboard() async {
    final token = await _ref.read(secureStorageProvider).readToken();
    _ref.read(authStateProvider.notifier).updateToken(token);
  }

  void cancelReplacement() {
    state = const HandshakeIdle();
  }

  void reset() {
    _cooldownUntil = null;
    state = const HandshakeIdle();
  }

  Future<void> _runHandshake(
    String pairingCode, {
    required bool confirmReplacement,
  }) async {
    if (state is HandshakeLoading) return;

    final retryAt = _cooldownUntil;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      state = HandshakeCooldown(
        message: 'Espera unos segundos antes de reintentar.',
        cooldownUntil: retryAt,
      );
      return;
    }

    _lastPairingCode = pairingCode;
    state = HandshakeLoading(
      confirmReplacement ? 'Confirmando reemplazo...' : 'Validando codigo...',
    );

    _lastFingerprint ??= await _deviceUuidService.getDeviceFingerprint();

    final result = await _repository.validatePairingCode(
      code: pairingCode,
      fingerprint: _lastFingerprint!,
      confirmReplacement: confirmReplacement,
    );

    await _applyResult(result);
  }

  Future<void> _applyResult(HandshakeResult result) async {
    switch (result) {
      case HandshakeSuccess(:final device):
        _cooldownUntil = null;
        await BackgroundServiceManager.startService();
        final geofenceService = _ref.read(geofenceServiceProvider);
        final safePlaceRepo = _ref.read(safePlaceRepositoryProvider);
        await geofenceService.syncFromBackend(safePlaceRepo);
        state = Success(device);
        return;

      case HandshakeRequiresConfirmation(:final conflict):
        _cooldownUntil = null;
        state = HandshakeConfirmationRequired(conflict);
        return;

      case HandshakeCodeExpired(:final message, :final cooldown):
        final retryAt = _startCooldown(cooldown);
        state = HandshakeCodeExpiredState(
          message: message,
          cooldownUntil: retryAt,
        );
        return;

      case HandshakeSessionRevoked(:final message):
        BackgroundServiceManager.stopService();
        await _ref.read(authStateProvider.notifier).deleteToken();
        state = HandshakeRevokedState(message);
        return;

      case HandshakeFailure(
        :final message,
        :final visualStatus,
        :final cooldown,
      ):
        final retryAt = _startCooldown(cooldown);
        state = HandshakeError(
          message: message,
          visualStatus: visualStatus,
          cooldownUntil: retryAt,
        );
        return;
    }
  }

  DateTime _startCooldown(Duration duration) {
    final retryAt = DateTime.now().add(duration);
    _cooldownUntil = retryAt;
    return retryAt;
  }
}

// Providers

final deviceUuidServiceProvider = Provider<DeviceUuidService>((ref) {
  return DeviceUuidService(secureStorage: ref.watch(secureStorageProvider));
});

final handshakeProvider =
    StateNotifierProvider<HandshakeNotifier, HandshakeState>((ref) {
      return HandshakeNotifier(
        repository: ref.watch(handshakeRepositoryProvider),
        deviceUuidService: ref.watch(deviceUuidServiceProvider),
        ref: ref,
      );
    });
