// lib/features/tracking/domain/services/movement_detector.dart
//
// Feature: Tracking — Detector de Movimiento con Debounce Anti-Fluctuación
//
// Problema: el GPS puede reportar velocidades ruidosas con variaciones pequeñas
// que provocarían cambios constantes entre STATIC y MOVING (efecto ping-pong).
//
// Solución — Sistema de lecturas consecutivas (hysteresis):
//   - MOVING: se activa solo cuando N lecturas CONSECUTIVAS superan el umbral.
//   - STATIC: se activa solo cuando N lecturas CONSECUTIVAS caen bajo el umbral.
//   - El umbral de activación (5 km/h) y desactivación (3 km/h) son diferentes
//     para crear una zona de histéresis que evita las fluctuaciones.
//
// Esto garantiza que pequeñas variaciones de GPS no causen cambios de estado.

import 'dart:developer' as dev;

// ── Constantes de calibración ─────────────────────────────────────────────────

/// Velocidad en m/s que activa el modo MOVING (5 km/h ≈ 1.39 m/s).
const double _kMovingThresholdMs = 1.39;

/// Velocidad en m/s que desactiva el modo MOVING (3 km/h ≈ 0.83 m/s).
/// El umbral inferior crea una histéresis para evitar fluctuaciones.
const double _kStaticThresholdMs = 0.83;

/// Número de lecturas consecutivas requeridas para ACTIVAR el modo MOVING.
const int _kConsecutiveReadingsToMove = 3;

/// Número de lecturas consecutivas requeridas para DESACTIVAR el modo MOVING.
const int _kConsecutiveReadingsToStop = 4;

// ─────────────────────────────────────────────────────────────────────────────

class MovementDetector {
  // ── Estado interno ──────────────────────────────────────────────────────────

  /// Estado de movimiento actual.
  bool _isMoving = false;

  /// Contador de lecturas consecutivas que superan el umbral de movimiento.
  int _movingCount = 0;

  /// Contador de lecturas consecutivas que caen bajo el umbral estático.
  int _staticCount = 0;

  // ── API Pública ─────────────────────────────────────────────────────────────

  /// Estado de movimiento actual. true = en movimiento, false = estático.
  bool get isMoving => _isMoving;

  /// Procesa una nueva lectura de velocidad GPS y actualiza el estado interno.
  ///
  /// [speedMs]: Velocidad en metros por segundo (campo `speed` de `Position`).
  ///
  /// Retorna true si el estado cambió (útil para detectar transiciones).
  bool update(double speedMs) {
    final bool previousState = _isMoving;

    if (!_isMoving) {
      // ── Evaluando si debe pasar a MOVING ─────────────────────────────────
      if (speedMs >= _kMovingThresholdMs) {
        _movingCount++;
        _staticCount = 0; // Reset del contador opuesto

        if (_movingCount >= _kConsecutiveReadingsToMove) {
          _isMoving = true;
          _movingCount = 0;
          dev.log(
            '[MovementDetector] ▶ STATIC → MOVING '
            '(speed: ${speedMs.toStringAsFixed(2)} m/s = '
            '${(speedMs * 3.6).toStringAsFixed(1)} km/h)',
            name: 'MovementDetector',
          );
        }
      } else {
        _movingCount = 0; // Romper la racha si la velocidad cae
      }
    } else {
      // ── Evaluando si debe pasar a STATIC ─────────────────────────────────
      if (speedMs < _kStaticThresholdMs) {
        _staticCount++;
        _movingCount = 0; // Reset del contador opuesto

        if (_staticCount >= _kConsecutiveReadingsToStop) {
          _isMoving = false;
          _staticCount = 0;
          dev.log(
            '[MovementDetector] ■ MOVING → STATIC '
            '(speed: ${speedMs.toStringAsFixed(2)} m/s = '
            '${(speedMs * 3.6).toStringAsFixed(1)} km/h)',
            name: 'MovementDetector',
          );
        }
      } else {
        _staticCount = 0; // Romper la racha si la velocidad sube de nuevo
      }
    }

    return _isMoving != previousState;
  }

  /// Resetea el detector a su estado inicial.
  void reset() {
    _isMoving = false;
    _movingCount = 0;
    _staticCount = 0;
  }
}
