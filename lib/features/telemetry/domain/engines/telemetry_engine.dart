// lib/features/telemetry/domain/engines/telemetry_engine.dart
//
// Feature: Telemetry — Motor de Captura de Telemetría (PRODUCCIÓN)
//
// Lógica de intervalo DINÁMICO:
//   - Si el dispositivo se está moviendo (speed > 0.5 m/s ≈ caminando)
//     → intervalo ACTIVO de 5 segundos para seguimiento en tiempo real.
//   - Si el dispositivo está estático (speed ≤ 0.5 m/s)
//     → intervalo PASIVO de 30 segundos para ahorrar batería y datos.
//
// Sensores reales:
//   - GPS:     geolocator.getCurrentPosition() con alta precisión.
//   - Batería: battery_plus.batteryLevel + batteryState (cargando o no).
//   - Red:     connectivity_plus para decidir modo online/offline.

import 'dart:async';
import 'dart:developer' as dev;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/repositories/telemetry_repository_impl.dart';
import '../services/sync_service.dart';

// ── Constantes de intervalo dinámico ─────────────────────────────────────────

/// Umbral de velocidad en m/s que activa el modo activo.
/// 0.5 m/s ≈ caminar lento — cualquier cosa superior activa el intervalo corto.
const double _kMovementThresholdMs = 0.5;

/// Intervalo rápido: dispositivo en movimiento.
const Duration _kActiveInterval = Duration(seconds: 5);

/// Intervalo lento: dispositivo estático.
const Duration _kPassiveInterval = Duration(seconds: 30);

// ─────────────────────────────────────────────────────────────────────────────

class TelemetryEngine {
  final TelemetryRepositoryImpl _repository;

  Timer? _captureTimer;
  bool _isRunning = false;

  /// Intervalo actual activo (empieza en pasivo por defecto).
  Duration _currentInterval = _kPassiveInterval;

  /// Instancia reutilizable del plugin de batería.
  final _battery = Battery();

  TelemetryEngine(this._repository);

  bool get isRunning => _isRunning;

  // ── Ciclo de vida ───────────────────────────────────────────────────────────

  void start() {
    if (_isRunning) return;
    _isRunning = true;

    dev.log(
      '[TelemetryEngine] Iniciado — intervalo inicial: ${_currentInterval.inSeconds}s.',
      name: 'TelemetryEngine',
    );

    // Primera captura inmediata para no esperar el primer tick del timer
    _captureAndProcess();

    // Inicia el timer periódico con el intervalo actual
    _scheduleNextCapture();
  }

  void stop() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _isRunning = false;
    dev.log('[TelemetryEngine] Detenido.', name: 'TelemetryEngine');
  }

  // ── Timer dinámico ──────────────────────────────────────────────────────────

  /// Programa el siguiente ciclo de captura con el intervalo correcto.
  ///
  /// Se re-evalúa después de cada captura para ajustar el intervalo
  /// según si el dispositivo estaba en movimiento o estático.
  void _scheduleNextCapture() {
    _captureTimer?.cancel();
    _captureTimer = Timer(_currentInterval, () async {
      await _captureAndProcess();
      if (_isRunning) _scheduleNextCapture(); // Re-programar con el nuevo intervalo
    });
  }

  // ── Lógica principal de captura ─────────────────────────────────────────────

  Future<void> _captureAndProcess() async {
    try {
      // 1. Leer conectividad actual
      final results = await Connectivity().checkConnectivity();
      final connectionType = _toConnectionString(results);

      // 2. Leer GPS real del hardware
      final position = await _readGps();

      // 3. Ajustar intervalo dinámico según velocidad del GPS
      _adjustInterval(position?.speed ?? 0.0);

      // 4. Leer nivel de batería y estado de carga reales
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      final isCharging = batteryState == BatteryState.charging ||
          batteryState == BatteryState.full;

      // 5. Usar coordenadas reales o 0.0 si el GPS no pudo obtener fix
      final lat = position?.latitude ?? 0.0;
      final lng = position?.longitude ?? 0.0;

      dev.log(
        '[TelemetryEngine] Captura — lat: $lat | lng: $lng | '
        'speed: ${position?.speed.toStringAsFixed(2)} m/s | '
        'battery: $batteryLevel% (charging: $isCharging) | '
        'interval: ${_currentInterval.inSeconds}s | '
        'connection: $connectionType',
        name: 'TelemetryEngine',
      );

      // 6. Enviar al repositorio (online → API / offline → SQLite)
      await _repository.processTelemetryFrame(
        lat: lat,
        lng: lng,
        battery: batteryLevel,
        isCharging: isCharging,
        connectionType: connectionType,
      );
    } catch (e, st) {
      dev.log(
        '[TelemetryEngine] Error en captura: $e',
        name: 'TelemetryEngine',
        error: e,
        stackTrace: st,
      );
    }
  }

  // ── Lectura de GPS ──────────────────────────────────────────────────────────

  /// Obtiene la posición GPS actual con alta precisión.
  ///
  /// Retorna null si el servicio de ubicación está deshabilitado o si
  /// los permisos no fueron concedidos (el engine no debe lanzar excepciones
  /// de permisos — esas deben manejarse en la UI antes de iniciar el servicio).
  Future<Position?> _readGps() async {
    try {
      // Verificar que el servicio de ubicación esté habilitado en el dispositivo
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        dev.log(
          '[TelemetryEngine] Servicio GPS deshabilitado en el dispositivo.',
          name: 'TelemetryEngine',
        );
        return null;
      }

      // Verificar permisos (ya deben haber sido concedidos en la UI)
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        dev.log(
          '[TelemetryEngine] Permiso de ubicación denegado: $permission',
          name: 'TelemetryEngine',
        );
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // timeLimit: evita bloquear el timer indefinidamente si el GPS tarda
          timeLimit: Duration(seconds: 4),
        ),
      );
    } on TimeoutException {
      dev.log(
        '[TelemetryEngine] GPS timeout — usando última posición conocida.',
        name: 'TelemetryEngine',
      );
      return Geolocator.getLastKnownPosition();
    } catch (e) {
      dev.log(
        '[TelemetryEngine] Error al leer GPS: $e',
        name: 'TelemetryEngine',
        error: e,
      );
      return null;
    }
  }

  // ── Lógica de intervalo dinámico ────────────────────────────────────────────

  /// Ajusta el intervalo de captura basándose en la velocidad del dispositivo.
  ///
  /// Si [speedMs] supera el umbral de movimiento, activa el intervalo rápido
  /// (5s). Si el dispositivo está quieto, cambia al intervalo lento (30s).
  void _adjustInterval(double speedMs) {
    final newInterval = speedMs > _kMovementThresholdMs
        ? _kActiveInterval   // En movimiento → 5s
        : _kPassiveInterval; // Estático → 30s

    if (newInterval != _currentInterval) {
      _currentInterval = newInterval;
      dev.log(
        '[TelemetryEngine] Intervalo ajustado a ${_currentInterval.inSeconds}s '
        '(speed: ${speedMs.toStringAsFixed(2)} m/s)',
        name: 'TelemetryEngine',
      );
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _toConnectionString(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return 'wifi';
    if (results.contains(ConnectivityResult.mobile)) return 'cellular';
    return 'none';
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final telemetryEngineProvider = Provider<TelemetryEngine>((ref) {
  final engine = TelemetryEngine(ref.read(telemetryRepositoryProvider));

  // Activar el SyncService para que la cola offline se drene
  // automáticamente cuando la conectividad se recupera.
  ref.read(syncServiceProvider);

  ref.onDispose(engine.stop);
  return engine;
});
