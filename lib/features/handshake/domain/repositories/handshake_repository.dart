// lib/features/handshake/domain/repositories/handshake_repository.dart
//
// Feature: Handshake - Capa Domain
// Contrato abstracto del repositorio de Handshake. Flutter no decide reglas de
// seguridad; solo interpreta resultados ya decididos por el backend.

import '../../../../core/services/device_uuid_service.dart';

/// Estado visual normalizado para el flujo de vinculacion.
///
/// El backend sigue siendo la autoridad. Este enum solo permite que Flutter
/// pinte mensajes y badges consistentes sin decidir ownership ni seguridad.
enum PairingLifecycleStatus { pending, paired, active, revoked, offline }

/// Informacion segura que el backend devuelve tras una vinculacion exitosa.
class PairedDeviceInfo {
  final String alias;
  final PairingLifecycleStatus status;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final String fingerprint;
  final String model;
  final String manufacturer;
  final String androidVersion;
  final String appVersion;

  const PairedDeviceInfo({
    required this.alias,
    required this.status,
    required this.fingerprint,
    required this.model,
    required this.manufacturer,
    required this.androidVersion,
    required this.appVersion,
    this.pairedAt,
    this.lastSeenAt,
  });
}

/// Detalle de conflicto devuelto por el backend cuando requiere confirmacion.
class PairingConflict {
  final String alias;
  final DateTime? lastSeenAt;
  final String message;
  final String fingerprint;

  const PairingConflict({
    required this.alias,
    required this.message,
    required this.fingerprint,
    this.lastSeenAt,
  });
}

/// Resultado tipado del proceso de vinculacion.
/// Evita el uso de tipos dinamicos y clarifica el contrato.
sealed class HandshakeResult {
  const HandshakeResult();
}

/// La vinculacion fue exitosa y el token ha sido guardado.
final class HandshakeSuccess extends HandshakeResult {
  final PairedDeviceInfo device;
  const HandshakeSuccess(this.device);
}

/// El backend pide confirmacion explicita del usuario antes de reemplazar.
final class HandshakeRequiresConfirmation extends HandshakeResult {
  final PairingConflict conflict;
  const HandshakeRequiresConfirmation(this.conflict);
}

/// El codigo ya no puede usarse.
final class HandshakeCodeExpired extends HandshakeResult {
  final String message;
  final Duration cooldown;
  const HandshakeCodeExpired(
    this.message, {
    this.cooldown = const Duration(seconds: 3),
  });
}

/// El token o la sesion fueron revocados por el backend.
final class HandshakeSessionRevoked extends HandshakeResult {
  final String message;
  const HandshakeSessionRevoked(this.message);
}

/// La vinculacion fallo con un mensaje descriptivo del error.
final class HandshakeFailure extends HandshakeResult {
  final String message;
  final PairingLifecycleStatus visualStatus;
  final Duration cooldown;

  const HandshakeFailure(
    this.message, {
    this.visualStatus = PairingLifecycleStatus.pending,
    this.cooldown = const Duration(seconds: 3),
  });
}

/// Contrato que define las operaciones del modulo de Handshake.
abstract class HandshakeRepository {
  /// Valida el codigo de emparejamiento junto con el fingerprint local.
  ///
  /// [confirmReplacement] no decide seguridad. Solo transporta una decision
  /// explicita del usuario para que el backend vuelva a evaluar el reemplazo.
  Future<HandshakeResult> validatePairingCode({
    required String code,
    required DeviceFingerprint fingerprint,
    bool confirmReplacement,
  });
}
