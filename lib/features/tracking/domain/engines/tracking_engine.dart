// lib/features/tracking/domain/engines/tracking_engine.dart
//
// Feature: Tracking — Motor Central de Rastreo Inteligente
//
// ════════════════════════════════════════════════════════════════════════════
// CEREBRO DEL SISTEMA DE RASTREO — v2 (con clasificación de movimiento)
// ════════════════════════════════════════════════════════════════════════════
//
// Responsabilidades centralizadas:
//   1. Calcular el TrackingState combinando geofencing + movimiento.
//   2. Clasificar el tipo de movimiento (STATIC/WALKING/RUNNING/VEHICLE).
//   3. Calcular el intervalo de ubicación REFINADO (estado base × tipo movimiento).
//   4. Gestionar timers dinámicos de ubicación (frecuencia según estado + tipo).
//   5. Gestionar timer fijo de telemetría del dispositivo (siempre activo).
//   6. Coordinar envío de LocationFrame con movementType enriquecido.
//   7. Coordinar envío de DeviceStatusFrame (SIEMPRE, sin importar zona).
//   8. Emitir eventos inmediatos ante cambios de estado y de zona.
//
// FLUJO DE DATOS:
//   GPS lectura → MovementClassifier → GeofenceService → TrackingState
//              → MovementType → Intervalo refinado
//              → LocationFrame (con movementType) → LocationRepository
//              → DeviceStatusFrame → DeviceStatusRepository (siempre)
//
// FRECUENCIAS BASE (TrackingState):
//   SAFE_STATIC: 20min | SAFE_MOVING: 15min
//   UNSAFE_STATIC: 30s | UNSAFE_MOVING: 5s
//
// REFINAMIENTO POR MOVIMIENTO (sobre el intervalo base):
//   STATIC / WALKING: sin cambio (mantener base)
//   RUNNING + SAFE_MOVING:  8min  (mejorar precisión de rutas de carrera)
//   VEHICLE + SAFE_MOVING:  3min  (mayor densidad de puntos en ruta)
//   VEHICLE + UNSAFE_MOVING: 5s  (ya en máxima densidad, sin cambio)
//
// TELEMETRÍA DEL DISPOSITIVO: cada 60 segundos (siempre, sin importar estado).

import 'dart:async';
import 'dart:developer' as dev;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/repositories/device_status_repository.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/safe_place_repository.dart';
import '../models/device_status_frame.dart';
import '../models/geofence_zone.dart';
import '../models/location_frame.dart';
import '../models/movement_type.dart';
import '../models/tracking_state.dart';
import '../services/geofence_service.dart';
import '../services/movement_classifier.dart';

// ── Constantes ─────────────────────────────────────────────────────────────────

/// Intervalo de envío de estado del dispositivo (batería, señal, etc.).
/// Fijo, independiente del estado de rastreo. Siempre activo.
const Duration _kDeviceStatusInterval = Duration(seconds: 60);

/// Timeout máximo para lectura GPS (evita bloquear el timer).
const Duration _kGpsTimeout = Duration(seconds: 6);

// ─────────────────────────────────────────────────────────────────────────────

class TrackingEngine {
  final Ref _ref;

  // ── Servicios internos ────────────────────────────────────────────────────
  late final GeofenceService _geofence;
  late final MovementClassifier _classifier;
  late final LocationRepository _locationRepo;
  late final DeviceStatusRepository _deviceStatusRepo;

  final _battery = Battery();

  // ── Estado actual ─────────────────────────────────────────────────────────
  TrackingState _currentState = TrackingState.unsafeStatic;
  TrackingState get currentState => _currentState;

  MovementType _currentMovementType = MovementType.static_;
  MovementType get currentMovementType => _currentMovementType;

  /// Intervalo de ubicación efectivo (base refinado por movementType).
  Duration get effectiveLocationInterval =>
      _resolveSpeedBasedInterval(_classifier.smoothedSpeedMs);

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer? _locationTimer;
  Timer? _deviceStatusTimer;
  StreamSubscription<GeofenceEvent>? _geofenceSubscription;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // ── Última posición conocida ──────────────────────────────────────────────
  Position? _lastKnownPosition;

  /// Estado actual de la pantalla del dispositivo.
  /// Se inicializa en [true] (pantalla encendida al arrancar el servicio).
  /// Actualizable externamente mediante [setScreenActive] desde el observador
  /// de ciclo de vida de la app (AppLifecycleState).
  bool? _isScreenActive = true;

  /// Notifica al motor si la pantalla del dispositivo está encendida o apagada.
  /// Debe llamarse desde el widget raíz usando [WidgetsBindingObserver]:
  ///   - [AppLifecycleState.resumed]  → setScreenActive(true)
  ///   - [AppLifecycleState.paused]   → setScreenActive(false)
  ///   - [AppLifecycleState.inactive] → setScreenActive(false)
  void setScreenActive(bool isActive) {
    _isScreenActive = isActive;
  }

  TrackingEngine(this._ref) {
    _geofence = _ref.read(geofenceServiceProvider);
    _classifier = MovementClassifier();
    _locationRepo = _ref.read(locationRepositoryProvider);
    _deviceStatusRepo = _ref.read(deviceStatusRepositoryProvider);
  }

  // ── Ciclo de Vida ───────────────────────────────────────────────────────────

  void start() {
    if (_isRunning) return;
    _isRunning = true;

    dev.log(
      '[TrackingEngine] ▶ Iniciando — estado: ${_currentState.displayName} | '
      'tipo: ${_currentMovementType.apiName}',
      name: 'TrackingEngine',
    );

    // Suscribirse a eventos de geofencing para reaccionar INMEDIATAMENTE
    _geofenceSubscription = _geofence.events.listen(_onGeofenceEvent);

    // Captura inmediata antes del primer tick
    _captureAndProcessLocation();
    _captureAndSendDeviceStatus();

    // Iniciar timer de ubicación con el intervalo efectivo actual
    _restartLocationTimer();

    // Iniciar timer de telemetría del dispositivo (siempre fijo)
    _startDeviceStatusTimer();

    // Sincronización periódica de zonas seguras
    Timer.periodic(const Duration(minutes: 30), (_) async {
      try {
        final repo = _ref.read(safePlaceRepositoryProvider);
        await _geofence.syncFromBackend(repo);
      } catch (e) {
        dev.log('[TrackingEngine] Error syncing safe places: $e', name: 'TrackingEngine');
      }
    });
  }

  void stop() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _deviceStatusTimer?.cancel();
    _deviceStatusTimer = null;
    _geofenceSubscription?.cancel();
    _geofenceSubscription = null;
    _isRunning = false;
    dev.log('[TrackingEngine] ■ Detenido.', name: 'TrackingEngine');
  }

  /// Actualiza las zonas seguras configuradas.
  void updateGeofenceZones(List<GeofenceZone> zones) {
    _geofence.updateZones(
      zones,
      currentLat: _lastKnownPosition?.latitude,
      currentLng: _lastKnownPosition?.longitude,
    );
    dev.log(
      '[TrackingEngine] ${zones.length} zona(s) de geofencing actualizadas.',
      name: 'TrackingEngine',
    );
  }

  // ── Timers Dinámicos ────────────────────────────────────────────────────────

  /// Reinicia el timer de ubicación con el intervalo efectivo (base + refinamiento).
  void _restartLocationTimer() {
    _locationTimer?.cancel();
    final interval = effectiveLocationInterval;

    _locationTimer = Timer.periodic(interval, (_) async {
      await _captureAndProcessLocation();
    });

    dev.log(
      '[TrackingEngine] Timer ajustado → ${_formatDuration(interval)} '
      '(${_currentState.displayName} + ${_currentMovementType.apiName})',
      name: 'TrackingEngine',
    );
  }

  void _startDeviceStatusTimer() {
    _deviceStatusTimer?.cancel();
    _deviceStatusTimer = Timer.periodic(_kDeviceStatusInterval, (_) async {
      await _captureAndSendDeviceStatus();
    });
  }

  // ── Reacción a Eventos de Geofencing ────────────────────────────────────────

  /// Llamado INMEDIATAMENTE cuando el dispositivo entra o sale de una zona.
  Future<void> _onGeofenceEvent(GeofenceEvent event) async {
    dev.log(
      '[TrackingEngine] Evento de geofencing: ${event.type} "${event.zone.name}"',
      name: 'TrackingEngine',
    );

    _recalculateState();

    // Envío inmediato y sincronización ante cambio de zona
    await _captureAndProcessLocation(forceSync: true);
    await _captureAndSendDeviceStatus();
  }

  // ── Captura de Ubicación ────────────────────────────────────────────────────

  Future<void> _captureAndProcessLocation({bool forceSync = false}) async {
    try {
      final position = await _readGps();

      if (position != null) {
        _lastKnownPosition = position;
        final previousInterval = effectiveLocationInterval;

        // ── 1. Clasificar movimiento con histéresis multi-nivel ─────────────
        final typeChanged = _classifier.update(position.speed);
        final previousType = _currentMovementType;
        _currentMovementType = _classifier.currentType;

        // ── 2. Evaluar geofencing local ────────────────────────────────────
        _geofence.evaluate(position.latitude, position.longitude);

        // ── 3. Recalcular TrackingState (geofencing × isMoving) ────────────
        final previousState = _currentState;
        _recalculateState();

        // ── 4. Detectar cambios y ajustar timer ────────────────────────────
        final stateChanged = _currentState != previousState;
        final movementChanged = typeChanged && previousType != _currentMovementType;
        final intervalChanged = effectiveLocationInterval != previousInterval;

        if (stateChanged) {
          dev.log(
            '[TrackingEngine] ★ Cambio de TrackingState: '
            '${previousState.displayName} → ${_currentState.displayName}',
            name: 'TrackingEngine',
          );
        }

        if (movementChanged) {
          dev.log(
            '[TrackingEngine] ◆ Cambio de MovementType: '
            '${previousType.icon} ${previousType.apiName} → '
            '${_currentMovementType.icon} ${_currentMovementType.apiName} '
            '(${_classifier.smoothedSpeedKmh.toStringAsFixed(1)} km/h)',
            name: 'TrackingEngine',
          );
        }

        // Reiniciar timer si cambió el estado O el tipo de movimiento
        // (ambos pueden alterar el intervalo efectivo)
        if (stateChanged || movementChanged || intervalChanged) {
          _restartLocationTimer();
          forceSync = true; // Cambio de estado/tipo siempre fuerza el envío
        }

        // ── 5. Construir y enviar el frame enriquecido ─────────────────────
        final zone = _geofence.currentZone;
        final motivo = stateChanged ? 'STATE_CHANGE' : (movementChanged ? 'MOVEMENT_CHANGE' : (intervalChanged ? 'INTERVAL_CHANGE' : 'PERIODIC'));
        
        final frame = LocationFrame(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          speedMs: position.speed >= 0 ? position.speed : null,
          smoothedSpeedMs: _classifier.smoothedSpeedMs,
          altitude: position.altitude,
          bearing: position.heading.isNaN ? null : position.heading,
          movementType: _currentMovementType,
          trackingState: _currentState.displayName,
          isInsideSafeZone: _geofence.isInsideSafeZone,
          activeZoneName: zone?.name,
          speedKmh: _classifier.smoothedSpeedKmh,
          intervaloAplicado: effectiveLocationInterval.inSeconds,
          motivo: motivo,
          capturedAt: DateTime.now(),
        );

        await _locationRepo.processLocationFrame(frame, forceSync: forceSync);
      } else {
        // GPS no disponible: enviar última posición conocida si es forceSync
        if (forceSync && _lastKnownPosition != null) {
          final pos = _lastKnownPosition!;
          final zone = _geofence.currentZone;
          final frame = LocationFrame(
            latitude: pos.latitude,
            longitude: pos.longitude,
            smoothedSpeedMs: _classifier.smoothedSpeedMs,
            bearing: pos.heading.isNaN ? null : pos.heading,
            movementType: _currentMovementType,
            trackingState: _currentState.displayName,
            isInsideSafeZone: _geofence.isInsideSafeZone,
            activeZoneName: zone?.name,
            speedKmh: _classifier.smoothedSpeedKmh,
            intervaloAplicado: effectiveLocationInterval.inSeconds,
            motivo: 'FORCE_SYNC',
            capturedAt: DateTime.now(),
          );
          await _locationRepo.processLocationFrame(frame, forceSync: true);
        }
      }
    } catch (e, st) {
      dev.log(
        '[TrackingEngine] Error en captura de ubicación: $e',
        name: 'TrackingEngine',
        error: e,
        stackTrace: st,
      );
    }
  }

  // ── Captura de Estado del Dispositivo ──────────────────────────────────────

  /// Captura y envía el estado del dispositivo (batería, red, etc.).
  /// Se ejecuta SIEMPRE, sin importar el estado de geofencing.
  Future<void> _captureAndSendDeviceStatus() async {
    try {
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      final isCharging = batteryState == BatteryState.charging ||
          batteryState == BatteryState.full;

      final connectivityResults = await Connectivity().checkConnectivity();
      final connectionType = _resolveConnectionType(connectivityResults);
      final hasInternet = connectionType != ConnectionType.none;

      final activityStatus = _resolveActivityStatus(isCharging);

      final frame = DeviceStatusFrame(
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        connectionType: connectionType,
        hasInternetAccess: hasInternet,
        trackingState: _currentState.displayName,
        activityStatus: activityStatus,
        screenActive: _isScreenActive,
        capturedAt: DateTime.now(),
      );

      await _deviceStatusRepo.processStatusFrame(frame);
    } catch (e, st) {
      dev.log(
        '[TrackingEngine] Error al capturar estado del dispositivo: $e',
        name: 'TrackingEngine',
        error: e,
        stackTrace: st,
      );
    }
  }

  // ── Cálculo de TrackingState ────────────────────────────────────────────────

  /// Recalcula el TrackingState combinando geofencing y movimiento.
  /// El clasificador determina `isMoving` (cualquier tipo != STATIC).
  void _recalculateState() {
    final newState = TrackingStateX.from(
      isSafe: _geofence.isInsideSafeZone,
      isMoving: _classifier.isMoving,
    );
    _currentState = newState;
  }

  // ── Lectura de GPS ──────────────────────────────────────────────────────────

  Future<Position?> _readGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _kGpsTimeout,
          distanceFilter: 0,
        ),
      );
    } on TimeoutException {
      dev.log(
        '[TrackingEngine] GPS timeout — usando última posición conocida.',
        name: 'TrackingEngine',
      );
      return Geolocator.getLastKnownPosition();
    } catch (e) {
      dev.log(
        '[TrackingEngine] Error al leer GPS: $e',
        name: 'TrackingEngine',
        error: e,
      );
      return null;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  ConnectionType _resolveConnectionType(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return ConnectionType.wifi;
    if (results.contains(ConnectivityResult.mobile)) {
      return ConnectionType.cellular;
    }
    return ConnectionType.none;
  }

  String _resolveActivityStatus(bool isCharging) {
    if (isCharging) return 'CHARGING';
    switch (_currentMovementType) {
      case MovementType.static_:
        return 'IDLE';
      case MovementType.walking:
        return 'WALKING';
      case MovementType.running:
        return 'RUNNING';
      case MovementType.vehicle:
        return 'IN_VEHICLE';
    }
  }

  /// Resuelve el intervalo de captura según velocidad y contexto de seguridad.
  /// Reglas objetivo:
  /// - Caminando: 5s
  /// - Corriendo: 4s
  /// - En auto/vehículo: 3s
  Duration _resolveSpeedBasedInterval(double speedMs) {
    final safe = _currentState.isSafe;
    final speed = speedMs < 0 ? 0.0 : speedMs;
    final speedKmh = speed * 3.6;

    if (safe) {
      if (speedKmh < 2.0) {
        return const Duration(seconds: 30);
      } else if (speedKmh < 7.0) {
        return const Duration(seconds: 5);
      } else if (speedKmh < 15.0) {
        return const Duration(seconds: 4);
      } else if (speedKmh < 80.0) {
        return const Duration(seconds: 3);
      } else {
        return const Duration(seconds: 2);
      }
    } else {
      if (speedKmh < 2.0) {
        return const Duration(seconds: 10);
      } else if (speedKmh < 7.0) {
        return const Duration(seconds: 5);
      } else if (speedKmh < 15.0) {
        return const Duration(seconds: 4);
      } else if (speedKmh < 80.0) {
        return const Duration(seconds: 3);
      } else {
        return const Duration(seconds: 2);
      }
    }
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}min';
    return '${d.inHours}h';
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final trackingEngineProvider = Provider<TrackingEngine>((ref) {
  final engine = TrackingEngine(ref);
  ref.onDispose(engine.stop);
  return engine;
});
