// lib/features/tracking/data/repositories/device_status_repository.dart
//
// Feature: Tracking — Repositorio de Estado del Dispositivo
//
// SEPARADO COMPLETAMENTE del repositorio de ubicación GPS.
//
// Responsabilidades:
//   1. Recibir DeviceStatusFrame del TrackingEngine.
//   2. Intentar envío online al endpoint de telemetría del backend.
//   3. Si falla o no hay conexión → encolar en SQLite.
//
// COMPORTAMIENTO CLAVE:
//   - Se envía SIEMPRE, sin importar el estado de geofencing ni el estado SAFE.
//   - Esto garantiza visibilidad completa del dispositivo incluso dentro de zonas seguras.

import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/services/local_database_service.dart';
import '../../../tracking/domain/models/device_status_frame.dart';

class DeviceStatusRepository {
  final Ref _ref;

  Dio get _dio => _ref.read(dioProvider);
  LocalDatabaseService get _localDb => _ref.read(localDatabaseProvider);

  const DeviceStatusRepository(this._ref);

  // ── API Pública ─────────────────────────────────────────────────────────────

  /// Procesa un frame de estado del dispositivo.
  /// Se envía SIEMPRE, sin importar el estado de geofencing.
  Future<void> processStatusFrame(DeviceStatusFrame frame) async {
    // Verificar conectividad
    final results = await Connectivity().checkConnectivity();
    final isOnline = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );

    if (isOnline) {
      final sent = await _trySendToApi(frame);
      if (sent) return;
    }

    // Offline o API falló: encolar localmente
    await _enqueueLocally(frame);
  }

  /// Drena la cola offline de estado del dispositivo en lotes.
  Future<void> drainOfflineQueue() async {
    final rows = await _localDb.getPendingDeviceStatusFrames();
    if (rows.isEmpty) return;

    dev.log(
      '[DeviceStatusRepo] Drenando ${rows.length} frame(s) de estado offline en lotes...',
      name: 'DeviceStatusRepository',
    );

    int success = 0;
    int failed = 0;
    const batchSize = 50;

    for (var i = 0; i < rows.length; i += batchSize) {
      final batchRows = rows.sublist(i, math.min(i + batchSize, rows.length));
      final batchIds = <int>[];
      final batchPayloads = <Map<String, dynamic>>[];

      for (final row in batchRows) {
        final id = row[LocalDatabaseService.colId] as int?;
        if (id != null) {
          try {
            final frame = DeviceStatusFrame.fromLocalMap(row);
            batchIds.add(id);
            batchPayloads.add(frame.toApiJson());
          } catch (e) {
            dev.log('[DeviceStatusRepo] Error parseando frame #$id: $e', name: 'DeviceStatusRepository');
          }
        }
      }

      if (batchPayloads.isEmpty) continue;

      try {
        final response = await _dio.post<Map<String, dynamic>>(
          'device-status/batch',
          data: {'frames': batchPayloads},
        );
        
        final status = response.statusCode ?? 0;
        if (status == 200 || status == 201) {
          await _localDb.deleteDeviceStatusFrames(batchIds);
          success += batchPayloads.length;
        } else {
          dev.log('[DeviceStatusRepo] Servidor rechazó lote — status: $status', name: 'DeviceStatusRepository');
          failed += batchPayloads.length;
        }
      } on DioException catch (e) {
        dev.log(
          '[DeviceStatusRepo] Error de red enviando lote: ${e.message}',
          name: 'DeviceStatusRepository',
        );
        failed += batchPayloads.length;
      } catch (e) {
        dev.log(
          '[DeviceStatusRepo] Error inesperado enviando lote: $e',
          name: 'DeviceStatusRepository',
          error: e,
        );
        failed += batchPayloads.length;
      }
    }

    dev.log(
      '[DeviceStatusRepo] Drenaje completado — ✓ $success | ✗ $failed',
      name: 'DeviceStatusRepository',
    );
  }

  // ── Helpers privados ────────────────────────────────────────────────────────

  Future<bool> _trySendToApi(DeviceStatusFrame frame) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'device-status',
        data: frame.toApiJson(),
      );
      final status = response.statusCode ?? 0;
      if (status == 200 || status == 201) {
        dev.log(
          '[DeviceStatusRepo] Estado enviado — battery: ${frame.batteryLevel}% | '
          'state: ${frame.trackingState} | conn: ${frame.connectionType.name}',
          name: 'DeviceStatusRepository',
        );
        return true;
      }
      return false;
    } on DioException catch (e) {
      dev.log(
        '[DeviceStatusRepo] DioException — ${e.type}: ${e.message}',
        name: 'DeviceStatusRepository',
        error: e,
      );
      return false;
    } catch (e, st) {
      dev.log(
        '[DeviceStatusRepo] Error inesperado: $e',
        name: 'DeviceStatusRepository',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<void> _enqueueLocally(DeviceStatusFrame frame) async {
    final id = await _localDb.insertDeviceStatusFrame(frame.toLocalMap());
    if (id >= 0) {
      dev.log(
        '[DeviceStatusRepo] Estado del dispositivo encolado offline — id: $id',
        name: 'DeviceStatusRepository',
      );
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final deviceStatusRepositoryProvider = Provider<DeviceStatusRepository>((ref) {
  return DeviceStatusRepository(ref);
});
