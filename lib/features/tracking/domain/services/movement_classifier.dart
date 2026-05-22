// lib/features/tracking/domain/services/movement_classifier.dart
//
// Feature: Tracking — Clasificador Inteligente de Tipo de Movimiento
//
// ════════════════════════════════════════════════════════════════════════════
// REEMPLAZA Y EXTIENDE A MovementDetector
// ════════════════════════════════════════════════════════════════════════════
//
// Clasifica el desplazamiento en 4 tipos usando velocidad GPS con una
// máquina de estados + histéresis multi-transición para evitar el efecto
// ping-pong entre categorías.
//
// DISEÑO DE HISTÉRESIS:
//   Cada transición tiene:
//     - Umbral de ENTRADA (más alto que el de salida)
//     - Umbral de SALIDA  (más bajo que el de entrada)
//     - Contador de lecturas consecutivas requerido
//
//   Esto crea una BANDA MUERTA entre cada par de estados donde el GPS
//   puede fluctuar libremente sin generar cambios de tipo.
//
//   Ejemplo: WALKING ↔ RUNNING
//     Entrada RUNNING: >= 2.2 m/s × 3 lecturas
//     Salida  RUNNING: <  1.7 m/s × 4 lecturas
//     Banda muerta:    1.7–2.2 m/s (segmento de amortiguación)
//
// VELOCIDADES EN m/s (1 km/h = 0.2778 m/s):
//   3  km/h = 0.833 m/s
//   7  km/h = 1.944 m/s
//   15 km/h = 4.167 m/s
//
// También expone `isMoving` (bool) para compatibilidad directa con
// el cálculo de TrackingState (SAFE/UNSAFE × STATIC/MOVING).

import 'dart:collection';
import 'dart:developer' as dev;

import '../models/movement_type.dart';

// ── Umbrales de transición (en m/s) ──────────────────────────────────────────

// STATIC → WALKING
const double _kWalkingEnter = 1.00; // 3.6 km/h (con margen sobre 3 km/h)
// WALKING → STATIC
const double _kWalkingExit = 0.72; // 2.6 km/h (banda muerta 0.72–1.00)

// WALKING → RUNNING
const double _kRunningEnter = 2.20; // 7.9 km/h (con margen sobre 7 km/h)
// RUNNING → WALKING
const double _kRunningExit = 1.70; // 6.1 km/h (banda muerta 1.70–2.20)

// RUNNING → VEHICLE
const double _kVehicleEnter = 4.50; // 16.2 km/h (con margen sobre 15 km/h)
// VEHICLE → RUNNING
const double _kVehicleExit = 3.90; // 14.0 km/h (banda muerta 3.90–4.50)

// ── Lecturas consecutivas requeridas por transición ───────────────────────────

// Transiciones hacia estados SUPERIORES (aceleración)
const int _kReadingsToWalking = 3; // STATIC → WALKING
const int _kReadingsToRunning = 3; // WALKING → RUNNING
const int _kReadingsToVehicle = 2; // RUNNING → VEHICLE (confirmación rápida)

// Transiciones hacia estados INFERIORES (desaceleración)
const int _kReadingsFromVehicle = 4; // VEHICLE → RUNNING
const int _kReadingsFromRunning = 4; // RUNNING → WALKING
const int _kReadingsFromWalking = 5; // WALKING → STATIC (más conservador)

// ── Ventana de velocidad promedio ─────────────────────────────────────────────

/// Tamaño de la ventana deslizante de velocidades para el promedio suavizado.
const int _kSpeedWindowSize = 5;

// ─────────────────────────────────────────────────────────────────────────────

class MovementClassifier {
  // ── Estado actual ──────────────────────────────────────────────────────────
  MovementType _currentType = MovementType.static_;
  MovementType get currentType => _currentType;

  /// true si el dispositivo está en cualquier forma de movimiento.
  /// Compatibilidad con TrackingEngine para calcular TrackingState.
  bool get isMoving => _currentType.isMoving;

  // ── Contadores de lecturas consecutivas (solo el activo importa) ───────────
  int _consecutiveCount = 0;

  /// Tipo objetivo de la transición en curso (null = sin transición activa).
  MovementType? _pendingType;

  // ── Ventana deslizante de velocidad suavizada ──────────────────────────────
  final Queue<double> _speedWindow = Queue<double>();
  double _smoothedSpeed = 0.0;

  /// Velocidad GPS suavizada actual (promedio de la ventana deslizante).
  double get smoothedSpeedMs => _smoothedSpeed;

  /// Velocidad en km/h (para display y logs).
  double get smoothedSpeedKmh => _smoothedSpeed * 3.6;

  // ── API Pública ─────────────────────────────────────────────────────────────

  /// Procesa una nueva lectura de velocidad GPS y actualiza el tipo de movimiento.
  ///
  /// [speedMs]: Velocidad en m/s del campo `Position.speed` de geolocator.
  ///            Valores negativos son tratados como 0 (GPS reporta -1 sin fix).
  ///
  /// Retorna true si el tipo de movimiento CAMBIÓ en esta lectura.
  bool update(double speedMs) {
    // Normalizar: GPS puede reportar -1 cuando no hay fix de velocidad
    final speed = speedMs < 0 ? 0.0 : speedMs;

    // Actualizar ventana deslizante y recalcular promedio suavizado
    _updateSpeedWindow(speed);

    final previousType = _currentType;

    // Evaluar la transición adecuada según el estado actual
    _evaluateTransition(_smoothedSpeed);

    return _currentType != previousType;
  }

  /// Resetea el clasificador a su estado inicial.
  void reset() {
    _currentType = MovementType.static_;
    _pendingType = null;
    _consecutiveCount = 0;
    _speedWindow.clear();
    _smoothedSpeed = 0.0;
  }

  // ── Máquina de Estados ─────────────────────────────────────────────────────

  void _evaluateTransition(double speed) {
    switch (_currentType) {
      case MovementType.static_:
        _tryTransitionUp(
          speed: speed,
          targetType: MovementType.walking,
          enterThreshold: _kWalkingEnter,
          requiredReadings: _kReadingsToWalking,
        );

      case MovementType.walking:
        // Evaluar si sube a RUNNING
        final wentUp = _tryTransitionUp(
          speed: speed,
          targetType: MovementType.running,
          enterThreshold: _kRunningEnter,
          requiredReadings: _kReadingsToRunning,
        );
        // Solo evaluar bajada si no hay transición subiendo en curso
        if (!wentUp) {
          _tryTransitionDown(
            speed: speed,
            targetType: MovementType.static_,
            exitThreshold: _kWalkingExit,
            requiredReadings: _kReadingsFromWalking,
          );
        }

      case MovementType.running:
        final wentUp = _tryTransitionUp(
          speed: speed,
          targetType: MovementType.vehicle,
          enterThreshold: _kVehicleEnter,
          requiredReadings: _kReadingsToVehicle,
        );
        if (!wentUp) {
          _tryTransitionDown(
            speed: speed,
            targetType: MovementType.walking,
            exitThreshold: _kRunningExit,
            requiredReadings: _kReadingsFromRunning,
          );
        }

      case MovementType.vehicle:
        _tryTransitionDown(
          speed: speed,
          targetType: MovementType.running,
          exitThreshold: _kVehicleExit,
          requiredReadings: _kReadingsFromVehicle,
        );
    }
  }

  /// Intenta iniciar o continuar una transición hacia un estado SUPERIOR.
  ///
  /// Retorna true si hay una transición hacia arriba en curso
  /// (para suprimir la evaluación de bajada simultánea).
  bool _tryTransitionUp({
    required double speed,
    required MovementType targetType,
    required double enterThreshold,
    required int requiredReadings,
  }) {
    if (speed >= enterThreshold) {
      if (_pendingType == targetType) {
        _consecutiveCount++;
      } else {
        // Iniciar nueva racha hacia este target
        _pendingType = targetType;
        _consecutiveCount = 1;
      }

      if (_consecutiveCount >= requiredReadings) {
        _commitTransition(targetType);
      }
      return true;
    } else {
      // La racha se rompe si el tipo objetivo era subir a este target
      if (_pendingType == targetType) {
        _pendingType = null;
        _consecutiveCount = 0;
      }
      return false;
    }
  }

  /// Intenta iniciar o continuar una transición hacia un estado INFERIOR.
  void _tryTransitionDown({
    required double speed,
    required MovementType targetType,
    required double exitThreshold,
    required int requiredReadings,
  }) {
    if (speed < exitThreshold) {
      if (_pendingType == targetType) {
        _consecutiveCount++;
      } else {
        _pendingType = targetType;
        _consecutiveCount = 1;
      }

      if (_consecutiveCount >= requiredReadings) {
        _commitTransition(targetType);
      }
    } else {
      if (_pendingType == targetType) {
        _pendingType = null;
        _consecutiveCount = 0;
      }
    }
  }

  /// Confirma y aplica la transición de tipo de movimiento.
  void _commitTransition(MovementType newType) {
    final previous = _currentType;
    _currentType = newType;
    _pendingType = null;
    _consecutiveCount = 0;

    dev.log(
      '[MovementClassifier] ${previous.icon} ${previous.apiName} → '
      '${newType.icon} ${newType.apiName} '
      '(${_smoothedSpeed.toStringAsFixed(2)} m/s = '
      '${(_smoothedSpeed * 3.6).toStringAsFixed(1)} km/h)',
      name: 'MovementClassifier',
    );
  }

  // ── Velocidad Suavizada ────────────────────────────────────────────────────

  void _updateSpeedWindow(double speed) {
    _speedWindow.addLast(speed);
    if (_speedWindow.length > _kSpeedWindowSize) {
      _speedWindow.removeFirst();
    }

    // Recalcular promedio de la ventana
    _smoothedSpeed = _speedWindow.isEmpty
        ? 0.0
        : _speedWindow.reduce((a, b) => a + b) / _speedWindow.length;
  }
}
