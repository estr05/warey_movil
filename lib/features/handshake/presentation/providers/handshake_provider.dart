// lib/features/handshake/presentation/providers/handshake_provider.dart
//
// Feature: Handshake — Capa Presentation (Gestión de Estado)
// StateNotifier que controla el ciclo de vida del proceso de vinculación.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/handshake_repository_impl.dart';
import '../../domain/repositories/handshake_repository.dart';
import '../../../../core/services/device_uuid_service.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/services/background_service.dart';
import '../../../../core/router/app_router.dart';

// ── Definición de estados ─────────────────────────────────────────────────────

/// Estado del proceso de vinculación. Sealed class de Dart 3 para exhaustividad.
sealed class HandshakeState {
  const HandshakeState();
}

/// Estado inicial: el formulario está listo para recibir input.
final class HandshakeIdle extends HandshakeState {
  const HandshakeIdle();
}

/// Validando el código con el servidor. El botón debe bloquearse.
final class HandshakeLoading extends HandshakeState {
  const HandshakeLoading();
}

/// El dispositivo fue vinculado con éxito (Success).
final class Success extends HandshakeState {
  const Success();
}

/// El proceso falló. [message] contiene la razón legible para el usuario.
final class HandshakeError extends HandshakeState {
  final String message;
  const HandshakeError(this.message);
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class HandshakeNotifier extends StateNotifier<HandshakeState> {
  final HandshakeRepository _repository;
  final DeviceUuidService _deviceUuidService;
  final Ref _ref;

  HandshakeNotifier({
    required HandshakeRepository repository,
    required DeviceUuidService deviceUuidService,
    required Ref ref,
  })  : _repository = repository,
        _deviceUuidService = deviceUuidService,
        _ref = ref,
        super(const HandshakeIdle());

  /// Inicia el proceso de vinculación.
  ///
  /// El UUID del hardware se obtiene internamente para que la UI
  /// solo necesite pasar el [pairingCode] tecleado por el usuario.
  Future<void> validatePairingCode(String pairingCode) async {
    // Evitar doble-tap si ya hay una operación en curso
    if (state is HandshakeLoading) return;

    state = const HandshakeLoading();

    // 1. Obtener el UUID del hardware de forma transparente
    final deviceUuid = await _deviceUuidService.getDeviceUuid();

    // 2. Delegar al repositorio
    final result = await _repository.validatePairingCode(
      code: pairingCode,
      deviceUuid: deviceUuid,
    );

    // 3. En caso de éxito, guardar token, arrancar telemetría y actualizar authState
    if (result is HandshakeSuccess) {
      // Despertar el hilo nativo de telemetría GPS inmediatamente
      await BackgroundServiceManager.startService();

      // Obtener el token de secure storage para actualizar el provider de autenticación
      final token = await _ref.read(secureStorageProvider).readToken();
      _ref.read(authStateProvider.notifier).updateToken(token);

      // Transicionar estado a Success
      state = const Success();
    } else if (result is HandshakeFailure) {
      state = HandshakeError(result.message);
    }
  }

  /// Resetea el estado a Idle (ej. cuando el usuario quiere volver a intentar).
  void reset() {
    state = const HandshakeIdle();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Provider del servicio de UUID (necesita ser expuesto para inyección).
final deviceUuidServiceProvider = Provider<DeviceUuidService>((ref) {
  return DeviceUuidService();
});

/// Provider del StateNotifier de Handshake.
/// La UI sólo debe escuchar este provider; no debe importar el Notifier.
final handshakeProvider =
    StateNotifierProvider<HandshakeNotifier, HandshakeState>((ref) {
  return HandshakeNotifier(
    repository: ref.watch(handshakeRepositoryProvider),
    deviceUuidService: ref.watch(deviceUuidServiceProvider),
    ref: ref,
  );
});
