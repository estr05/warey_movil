// lib/core/services/device_uuid_service.dart
//
// Capa Core — Servicio de Hardware UUID
// Responsabilidad: extraer el identificador único del dispositivo físico.
// Este UUID será usado en el handshake inicial con el servidor DevUbi
// para asociar el dispositivo a un usuario autenticado.

import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class DeviceUuidService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Retorna el UUID de hardware según la plataforma.
  ///
  /// - Android → [AndroidDeviceInfo.id] (androidId)
  /// - iOS     → [IosDeviceInfo.identifierForVendor]
  /// - Otras   → retorna un UUID de prueba formateado.
  Future<String> getDeviceUuid() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final rawId = androidInfo.id;
        return _formatOrFallback(rawId, 'android-unknown');
      }

      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final rawId = iosInfo.identifierForVendor;
        return _formatOrFallback(rawId, 'ios-unknown');
      }

      // Plataforma no soportada (Desktop, Web): retorna UUID de prueba.
      return _buildTestUuid('unsupported-platform');
    } catch (e) {
      // Si ocurre cualquier excepción de hardware, devuelve un UUID de prueba
      // con el prefijo del error para facilitar la depuración.
      return _buildTestUuid('error-${e.runtimeType}');
    }
  }

  // ── Helpers privados ────────────────────────────────────────────────────────

  /// Si el [rawId] es nulo o vacío, retorna un UUID de prueba con [fallbackTag].
  String _formatOrFallback(String? rawId, String fallbackTag) {
    if (rawId == null || rawId.isEmpty) {
      return _buildTestUuid(fallbackTag);
    }
    return rawId;
  }

  /// Construye un string de prueba con formato UUID-like para entornos
  /// donde el hardware no puede proveer un ID real.
  ///
  /// Formato: `TEST-<tag>-0000-0000-000000000000`
  String _buildTestUuid(String tag) {
    final sanitized = tag.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '_');
    return 'TEST-$sanitized-0000-0000-000000000000';
  }
}
