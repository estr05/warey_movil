// lib/features/handshake/domain/repositories/handshake_repository.dart
//
// Feature: Handshake — Capa Domain
// Contrato abstracto del repositorio de Handshake.
// La capa de presentación depende de esta abstracción, nunca de la implementación concreta.
// Esto permite intercambiar la fuente de datos (API real, mock) sin tocar la UI.

/// Resultado tipado del proceso de vinculación.
/// Evita el uso de tipos dinámicos y clarifica el contrato.
sealed class HandshakeResult {
  const HandshakeResult();
}

/// La vinculación fue exitosa y el token ha sido guardado.
final class HandshakeSuccess extends HandshakeResult {
  const HandshakeSuccess();
}

/// La vinculación falló con un mensaje descriptivo del error.
final class HandshakeFailure extends HandshakeResult {
  final String message;
  const HandshakeFailure(this.message);
}

/// Contrato que define las operaciones del módulo de Handshake.
abstract class HandshakeRepository {
  /// Valida el código de emparejamiento del panel Admin junto con el UUID
  /// del hardware del dispositivo. Si tiene éxito, persiste el token devuelto.
  Future<HandshakeResult> validatePairingCode({
    required String code,
    required String deviceUuid,
  });
}
