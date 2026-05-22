// lib/features/tracking/domain/models/movement_type.dart
//
// Feature: Tracking — Tipo de Movimiento del Dispositivo
//
// Clasifica el desplazamiento del dispositivo en 4 categorías basadas
// en velocidad GPS, estabilidad y aceleración.
//
// RELACIÓN CON TrackingState:
//   TrackingState (SAFE/UNSAFE × STATIC/MOVING) → define el INTERVALO BASE.
//   MovementType (STATIC/WALKING/RUNNING/VEHICLE)  → REFINA ese intervalo
//   y enriquece los datos enviados al backend para mejorar la calidad
//   de rutas, historial y análisis de comportamiento.
//
// ┌─────────────────────────────────────────────────────────────────┐
// │ Rangos de velocidad GPS                                         │
// │                                                                 │
// │  STATIC   < 3 km/h   (< 0.83 m/s)                             │
// │  WALKING  3–7 km/h   (0.83–1.94 m/s)                          │
// │  RUNNING  7–15 km/h  (1.94–4.17 m/s)                          │
// │  VEHICLE  > 15 km/h  (> 4.17 m/s)                             │
// └─────────────────────────────────────────────────────────────────┘

import '../models/tracking_state.dart';

/// Tipo de desplazamiento del dispositivo detectado por el clasificador.
enum MovementType {
  /// Detenido o con movimiento mínimo (< 3 km/h).
  static_,

  /// Caminando (3–7 km/h).
  walking,

  /// Corriendo (7–15 km/h).
  running,

  /// En vehículo (> 15 km/h).
  vehicle,
}

extension MovementTypeX on MovementType {
  /// Nombre legible para payload API y logs.
  String get apiName {
    switch (this) {
      case MovementType.static_:
        return 'STATIC';
      case MovementType.walking:
        return 'WALKING';
      case MovementType.running:
        return 'RUNNING';
      case MovementType.vehicle:
        return 'VEHICLE';
    }
  }

  /// Emoji de diagnóstico para logs.
  String get icon {
    switch (this) {
      case MovementType.static_:
        return '■';
      case MovementType.walking:
        return '🚶';
      case MovementType.running:
        return '🏃';
      case MovementType.vehicle:
        return '🚗';
    }
  }

  /// true si el dispositivo está en cualquier forma de movimiento.
  bool get isMoving => this != MovementType.static_;

  /// true si el tipo de movimiento requiere alta densidad de puntos GPS.
  /// En vehículo, la captura densa es crítica para evitar líneas rectas
  /// que no representan la ruta real (curvas, calles, giros).
  bool get requiresDenseCapture => this == MovementType.vehicle;

  /// true si el tipo de movimiento requiere precisión de ruta moderada.
  bool get requiresModeratePrecision => this == MovementType.running;

  /// Calcula el intervalo de ubicación REFINADO combinando el estado
  /// base de geofencing con el tipo de movimiento detectado.
  ///
  /// El [TrackingState] define el intervalo base (seguridad × movimiento).
  /// Este método aplica un refinamiento para mejorar la calidad de rutas
  /// sin sacrificar batería cuando no es necesario.
  Duration refinedInterval(TrackingState state) {
    final base = state.locationInterval;

    switch (this) {
      // ── STATIC / WALKING: mantener intervalos actuales ────────────────────
      case MovementType.static_:
      case MovementType.walking:
        return base;

      // ── RUNNING: aumentar ligeramente la precisión ────────────────────────
      case MovementType.running:
        switch (state) {
          case TrackingState.safeMoving:
            // 15min → 8min: mejor trazado de rutas de carrera en zona segura
            return const Duration(minutes: 8);
          case TrackingState.safeStatic:
          case TrackingState.unsafeStatic:
          case TrackingState.unsafeMoving:
            return base; // UNSAFE_MOVING ya es 5s (máxima densidad)
        }

      // ── VEHICLE: máxima densidad para continuidad de trayectoria ──────────
      case MovementType.vehicle:
        switch (state) {
          case TrackingState.safeMoving:
            // 15min → 3min: densidad suficiente para trazar rutas en calles
            return const Duration(minutes: 3);
          case TrackingState.unsafeMoving:
            // 5s → 5s: ya es máxima densidad, mantener
            return base;
          case TrackingState.safeStatic:
          case TrackingState.unsafeStatic:
            return base;
        }
    }
  }

  /// Reconstruye desde un string del API o SQLite.
  static MovementType fromString(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'WALKING':
        return MovementType.walking;
      case 'RUNNING':
        return MovementType.running;
      case 'VEHICLE':
        return MovementType.vehicle;
      default:
        return MovementType.static_;
    }
  }
}
