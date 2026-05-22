// lib/core/services/permission_service.dart
//
// Capa Core — Servicio de Solicitud de Permisos
// Responsabilidad: solicitar todos los permisos críticos del OS en orden correcto
// antes de que el usuario pueda iniciar el proceso de vinculación.
//
// Permisos requeridos:
//   - Notificaciones (Android 13+): para el canal de la notificación persistente.
//   - Ubicación mientras la app está en uso: requerido antes de pedir background.
//   - Ubicación en background (Android 10+): para el foreground service GPS.

import 'dart:developer' as dev;
import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Solicita todos los permisos necesarios para operar el nodo de telemetría.
  ///
  /// Retorna true si TODOS los permisos críticos fueron concedidos.
  /// Retorna false si algún permiso crítico fue denegado (la UI debe reaccionar).
  ///
  /// Orden de solicitud:
  ///   1. POST_NOTIFICATIONS (Android 13+) — no bloquea la telemetría si falla.
  ///   2. ACCESS_FINE_LOCATION — crítico, sin esto no hay GPS.
  ///   3. ACCESS_BACKGROUND_LOCATION (Android 10+) — necesario para el foreground service.
  static Future<PermissionResult> requestAll() async {
    dev.log('[PermissionService] Iniciando solicitud de permisos...', name: 'PermissionService');

    // ── 1. Notificaciones ───────────────────────────────────────────────────
    // Solo relevante en Android 13+. En iOS se maneja diferente (no bloqueante).
    if (Platform.isAndroid) {
      final notifStatus = await Permission.notification.request();
      dev.log('[PermissionService] Notificaciones: ${notifStatus.name}', name: 'PermissionService');
      // Continuar incluso si se niega — las notificaciones son deseables pero no críticas
    }

    // ── 2. Ubicación en primer plano ────────────────────────────────────────
    // DEBE solicitarse antes de pedir background location (requisito del OS).
    var locationStatus = await Permission.locationWhenInUse.status;

    if (!locationStatus.isGranted) {
      locationStatus = await Permission.locationWhenInUse.request();
    }

    dev.log('[PermissionService] Ubicación (foreground): ${locationStatus.name}', name: 'PermissionService');

    if (!locationStatus.isGranted) {
      return PermissionResult(
        granted: false,
        deniedPermission: 'Ubicación',
        isPermanentlyDenied: locationStatus.isPermanentlyDenied,
      );
    }

    // ── 3. Ubicación en background ──────────────────────────────────────────
    // Solo Android 10+. iOS no usa este permiso (lo maneja con UIBackgroundModes).
    if (Platform.isAndroid) {
      var bgLocationStatus = await Permission.locationAlways.status;

      if (!bgLocationStatus.isGranted) {
        // Android exige que el usuario sea llevado a la pantalla de ajustes del OS
        // si el permiso de background fue denegado anteriormente.
        bgLocationStatus = await Permission.locationAlways.request();
      }

      dev.log('[PermissionService] Ubicación (background): ${bgLocationStatus.name}', name: 'PermissionService');

      if (!bgLocationStatus.isGranted) {
        return PermissionResult(
          granted: false,
          deniedPermission: 'Ubicación en segundo plano',
          isPermanentlyDenied: bgLocationStatus.isPermanentlyDenied,
        );
      }
    }

    dev.log('[PermissionService] Todos los permisos críticos concedidos.', name: 'PermissionService');
    return const PermissionResult(granted: true);
  }

  /// Abre la pantalla de configuración del OS para que el usuario
  /// pueda conceder manualmente un permiso que fue denegado permanentemente.
  static Future<void> openSettings() => openAppSettings();
}

/// Resultado tipado de la solicitud de permisos.
class PermissionResult {
  /// true si todos los permisos críticos fueron concedidos.
  final bool granted;

  /// Nombre del permiso que fue denegado (null si [granted] es true).
  final String? deniedPermission;

  /// true si el usuario marcó "No volver a preguntar" — en ese caso
  /// la app debe redirigir al usuario a la configuración del sistema.
  final bool isPermanentlyDenied;

  const PermissionResult({
    required this.granted,
    this.deniedPermission,
    this.isPermanentlyDenied = false,
  });
}
