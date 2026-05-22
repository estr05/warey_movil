// lib/core/utils/permission_helper.dart
//
// Capa Core — Utilidad de Gestión de Permisos
// Centraliza las solicitudes de permisos críticos para el funcionamiento
// del servicio de telemetría: ubicación en primer y segundo plano,
// y notificaciones (requerido en Android 13+ para el foreground service).

import 'dart:developer' as dev;

import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  PermissionHelper._();

  /// Solicita todos los permisos requeridos por DevUbi en secuencia correcta.
  ///
  /// Orden obligatorio:
  ///   1. Notificación (Android 13+ — sin esto no se muestra el foreground)
  ///   2. Ubicación precisa (en uso)
  ///   3. Ubicación en segundo plano (solo DESPUÉS de que se concedió la precisa)
  ///
  /// Retorna [true] si todos los permisos críticos fueron concedidos.
  static Future<bool> requestAllPermissions() async {
    final notifGranted = await _requestNotification();
    final locationGranted = await _requestLocation();

    // locationAlways SOLO si la ubicación en uso fue concedida primero.
    // El OS rechaza automáticamente locationAlways si location no fue concedida.
    final alwaysGranted = locationGranted ? await _requestLocationAlways() : false;

    final allGranted = notifGranted && locationGranted && alwaysGranted;

    dev.log(
      '[Permissions] Resultado: notif=$notifGranted | location=$locationGranted | always=$alwaysGranted',
      name: 'PermissionHelper',
    );

    return allGranted;
  }

  /// Solo permisos de ubicación (en uso + segundo plano).
  /// Usar cuando la notificación ya fue concedida previamente.
  static Future<bool> requestLocationPermissions() async {
    final locationGranted = await _requestLocation();
    final alwaysGranted = locationGranted ? await _requestLocationAlways() : false;
    return locationGranted && alwaysGranted;
  }

  /// Verifica si todos los permisos ya fueron concedidos (sin solicitar).
  static Future<bool> areAllGranted() async {
    final statuses = await [
      Permission.notification,
      Permission.location,
      Permission.locationAlways,
    ].request(); // request() es idempotente si ya están concedidos

    return statuses.values.every((s) => s.isGranted);
  }

  /// Abre la configuración de la app para que el usuario conceda permisos
  /// que fueron denegados permanentemente.
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  // ── Helpers privados ──────────────────────────────────────────────────────

  static Future<bool> _requestNotification() async {
    if (await Permission.notification.isGranted) return true;
    final status = await Permission.notification.request();
    _log('notification', status);
    return status.isGranted;
  }

  static Future<bool> _requestLocation() async {
    if (await Permission.location.isGranted) return true;
    final status = await Permission.location.request();
    _log('location', status);
    if (status.isPermanentlyDenied) {
      dev.log('[Permissions] location denegado permanentemente. Abrir configuración.', name: 'PermissionHelper');
    }
    return status.isGranted;
  }

  static Future<bool> _requestLocationAlways() async {
    if (await Permission.locationAlways.isGranted) return true;
    final status = await Permission.locationAlways.request();
    _log('locationAlways', status);
    if (status.isPermanentlyDenied) {
      dev.log('[Permissions] locationAlways denegado permanentemente. Abrir configuración.', name: 'PermissionHelper');
    }
    return status.isGranted;
  }

  static void _log(String name, PermissionStatus status) {
    dev.log('[Permissions] $name → ${status.name}', name: 'PermissionHelper');
  }
}
