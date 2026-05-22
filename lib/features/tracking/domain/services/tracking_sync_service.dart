// lib/features/tracking/domain/services/tracking_sync_service.dart
//
// Feature: Tracking — Servicio de Sincronización Offline Unificado
//
// Responsabilidad: escuchar el stream de conectividad y, cuando la red
// se recupera, drenar AMBAS colas offline (ubicación + estado del dispositivo)
// hacia el backend en orden FIFO.
//
// Diferencia con el SyncService legacy:
//   - Conoce los dos repositorios separados (ubicación + telemetría).
//   - También escucha eventos de geofencing para sincronizar inmediatamente.
//   - Coordina el drenaje en paralelo de ambas colas.

import 'dart:async';
import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/device_status_repository.dart';
import '../../data/repositories/location_repository.dart';

class TrackingSyncService {
  final Ref _ref;

  LocationRepository get _locationRepo => _ref.read(locationRepositoryProvider);
  DeviceStatusRepository get _deviceStatusRepo =>
      _ref.read(deviceStatusRepositoryProvider);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isSyncing = false;

  TrackingSyncService(this._ref);

  // ── Ciclo de Vida ──────────────────────────────────────────────────────────

  void initialize() {
    dev.log(
      '[TrackingSyncService] Iniciando listener de conectividad...',
      name: 'TrackingSyncService',
    );

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged, onError: _onStreamError);
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    dev.log(
      '[TrackingSyncService] Listener cancelado.',
      name: 'TrackingSyncService',
    );
  }

  // ── Sincronización Manual ──────────────────────────────────────────────────

  /// Drena ambas colas offline inmediatamente.
  /// Útil para forzar sincronización tras un cambio de estado o zona.
  Future<void> syncNow() async {
    await _drainAllQueues();
  }

  // ── Lógica de Sincronización ───────────────────────────────────────────────

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final isOnline = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );

    dev.log(
      '[TrackingSyncService] Conectividad: ${results.map((r) => r.name).join(', ')} | online: $isOnline',
      name: 'TrackingSyncService',
    );

    if (!isOnline) return;

    await _drainAllQueues();
  }

  Future<void> _drainAllQueues() async {
    if (_isSyncing) {
      dev.log(
        '[TrackingSyncService] Sincronización ya en curso — omitiendo.',
        name: 'TrackingSyncService',
      );
      return;
    }

    _isSyncing = true;
    dev.log(
      '[TrackingSyncService] Iniciando drenaje de colas offline...',
      name: 'TrackingSyncService',
    );

    try {
      // Drenar ambas colas en paralelo para máxima eficiencia
      await Future.wait([
        _locationRepo.drainOfflineQueue(),
        _deviceStatusRepo.drainOfflineQueue(),
      ]);

      dev.log(
        '[TrackingSyncService] Drenaje completado.',
        name: 'TrackingSyncService',
      );
    } catch (e, st) {
      dev.log(
        '[TrackingSyncService] ERROR durante el drenaje: $e',
        name: 'TrackingSyncService',
        error: e,
        stackTrace: st,
      );
    } finally {
      _isSyncing = false;
    }
  }

  void _onStreamError(Object error, StackTrace st) {
    dev.log(
      '[TrackingSyncService] ERROR en el stream de conectividad: $error',
      name: 'TrackingSyncService',
      error: error,
      stackTrace: st,
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final trackingSyncServiceProvider = Provider<TrackingSyncService>((ref) {
  final service = TrackingSyncService(ref);
  service.initialize();
  ref.onDispose(service.dispose);
  return service;
});
