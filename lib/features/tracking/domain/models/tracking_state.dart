// lib/features/tracking/domain/models/tracking_state.dart
//
// Feature: Tracking — Modelo de Estado de Rastreo
//
// Define los 4 estados posibles del dispositivo, combinando:
//   - Seguridad: si el dispositivo está dentro de una zona segura (geofence).
//   - Movimiento: si el dispositivo está en movimiento o estático.
//
// Cada estado tiene asociada una frecuencia de envío de ubicación.
// La telemetría del dispositivo (batería, señal, etc.) se envía siempre,
// independientemente del estado.

/// Estado combinado del dispositivo: seguridad × movimiento.
enum TrackingState {
  /// Dentro de zona segura, sin movimiento significativo.
  /// Frecuencia de ubicación: cada 20 minutos.
  safeStatic,

  /// Dentro de zona segura, en movimiento (>= 5 km/h).
  /// Frecuencia de ubicación: cada 15 minutos.
  safeMoving,

  /// Fuera de zonas seguras, sin movimiento significativo.
  /// Frecuencia de ubicación: cada 30 segundos.
  unsafeStatic,

  /// Fuera de zonas seguras, en movimiento (>= 5 km/h).
  /// Frecuencia de ubicación: cada 5 segundos.
  unsafeMoving,
}

extension TrackingStateX on TrackingState {
  /// Intervalo de envío de ubicación GPS para este estado.
  Duration get locationInterval {
    switch (this) {
      case TrackingState.safeStatic:
        return const Duration(minutes: 20);
      case TrackingState.safeMoving:
        return const Duration(minutes: 15);
      case TrackingState.unsafeStatic:
        return const Duration(seconds: 30);
      case TrackingState.unsafeMoving:
        return const Duration(seconds: 5);
    }
  }

  /// Nombre legible para logs y notificaciones.
  String get displayName {
    switch (this) {
      case TrackingState.safeStatic:
        return 'SAFE_STATIC';
      case TrackingState.safeMoving:
        return 'SAFE_MOVING';
      case TrackingState.unsafeStatic:
        return 'UNSAFE_STATIC';
      case TrackingState.unsafeMoving:
        return 'UNSAFE_MOVING';
    }
  }

  /// true si el dispositivo está dentro de una zona segura.
  bool get isSafe {
    return this == TrackingState.safeStatic ||
        this == TrackingState.safeMoving;
  }

  /// true si el dispositivo está en movimiento.
  bool get isMoving {
    return this == TrackingState.safeMoving ||
        this == TrackingState.unsafeMoving;
  }

  /// Construye el estado combinando la bandera de seguridad y movimiento.
  static TrackingState from({required bool isSafe, required bool isMoving}) {
    if (isSafe && !isMoving) return TrackingState.safeStatic;
    if (isSafe && isMoving) return TrackingState.safeMoving;
    if (!isSafe && !isMoving) return TrackingState.unsafeStatic;
    return TrackingState.unsafeMoving;
  }
}
