// lib/features/tracking/data/repositories/location_repository.dart
//
// Feature: Tracking — Repositorio de Ubicación GPS
//
// SEPARADO COMPLETAMENTE del repositorio de telemetría del dispositivo.
//
// Responsabilidades:
//   1. Recibir LocationFrame del TrackingEngine.
//   2. Aplicar filtro de distancia mínima para evitar coordenadas redundantes.
//   3. Intentar envío online al endpoint de ubicación del backend.
//   4. Si falla o no hay conexión → encolar en SQLite (cola offline de ubicación).
//
// Filtro de redundancia:
//   - Si la distancia entre la última ubicación enviada y la nueva es menor
//     que el umbral mínimo, el frame se descarta (salvo si hubo cambio de estado).
//   - Esto reduce drásticamente el tráfico en estados SAFE donde el dispositivo
//     está quieto y el GPS oscila pocos metros.

import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/services/local_database_service.dart';
import '../../../tracking/domain/models/location_frame.dart';

// ── Constantes de filtro ──────────────────────────────────────────────────────

/// Distancia mínima en metros para considerar una ubicación significativa.
/// Por debajo de este umbral, la ubicación es descartada como redundante.
const double _kMinDistanceMeters = 15.0;

// ─────────────────────────────────────────────────────────────────────────────

class LocationRepository {
  final Ref _ref;

  Dio get _dio => _ref.read(dioProvider);
  LocalDatabaseService get _localDb => _ref.read(localDatabaseProvider);

  // Última ubicación enviada exitosamente para filtro de redundancia
  double? _lastSentLat;
  double? _lastSentLng;

  // Último estado enviado (para forzar envío en cambios de estado)
  String? _lastSentState;

  LocationRepository(this._ref);

  // ── API Pública ─────────────────────────────────────────────────────────────

  /// Procesa un frame de ubicación:
  ///   1. Aplica filtro de distancia mínima.
  ///   2. Si pasa el filtro → intenta envío online o encola offline.
  ///
  /// [forceSync]: si true, omite el filtro de distancia (usado en cambios de estado).
  Future<void> processLocationFrame(
    LocationFrame frame, {
    bool forceSync = false,
  }) async {
    // ── 1. Filtro de redundancia ──────────────────────────────────────────
    if (!forceSync && !_isSignificantChange(frame)) {
      dev.log(
        '[LocationRepo] Frame descartado — movimiento insignificante '
        '(< ${_kMinDistanceMeters}m desde la última ubicación enviada).',
        name: 'LocationRepository',
      );
      return;
    }

    // ── 2. Verificar conectividad ─────────────────────────────────────────
    final results = await Connectivity().checkConnectivity();
    final isOnline = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );

    if (isOnline) {
      final sent = await _trySendToApi(frame);
      if (sent) {
        _updateLastSent(frame);
        return;
      }
    }

    // ── 3. Offline o API falló: encolar localmente ────────────────────────
    await _enqueueLocally(frame);
  }

  /// Drena la cola offline de ubicación enviando los frames pendientes en lotes.
  /// Llamar cuando se recupere la conectividad.
  Future<void> drainOfflineQueue() async {
    final rows = await _localDb.getPendingLocationFrames();
    if (rows.isEmpty) return;

    dev.log(
      '[LocationRepo] Drenando ${rows.length} frame(s) de ubicación offline en lotes...',
      name: 'LocationRepository',
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
            final frame = LocationFrame.fromLocalMap(row);
            batchIds.add(id);
            batchPayloads.add(frame.toApiJson());
          } catch (e) {
            dev.log('[LocationRepo] Error parseando frame #$id: $e', name: 'LocationRepository');
          }
        }
      }

      if (batchPayloads.isEmpty) continue;

      try {
        final response = await _dio.post<Map<String, dynamic>>(
          'location/batch',
          data: {'frames': batchPayloads},
        );
        
        final status = response.statusCode ?? 0;
        if (status == 200 || status == 201) {
          await _localDb.deleteLocationFrames(batchIds);
          success += batchPayloads.length;
        } else {
          dev.log('[LocationRepo] Servidor rechazó lote — status: $status', name: 'LocationRepository');
          failed += batchPayloads.length;
        }
      } on DioException catch (e) {
        dev.log(
          '[LocationRepo] Error de red enviando lote: ${e.message}',
          name: 'LocationRepository',
        );
        failed += batchPayloads.length;
      } catch (e) {
        dev.log(
          '[LocationRepo] Error inesperado enviando lote: $e',
          name: 'LocationRepository',
          error: e,
        );
        failed += batchPayloads.length;
      }
    }

    dev.log(
      '[LocationRepo] Drenaje completado — ✓ $success | ✗ $failed',
      name: 'LocationRepository',
    );
  }

  // ── Helpers privados ────────────────────────────────────────────────────────

  /// Evalúa si la nueva ubicación es suficientemente diferente de la última
  /// enviada para justificar un nuevo envío.
  bool _isSignificantChange(LocationFrame frame) {
    // Si es la primera ubicación, siempre es significativa
    if (_lastSentLat == null || _lastSentLng == null) return true;

    // Si el estado de rastreo cambió, forzar envío
    if (_lastSentState != frame.trackingState) return true;

    // Calcular distancia con Haversine simplificado
    final distance = _haversineDistanceMeters(
      _lastSentLat!,
      _lastSentLng!,
      frame.latitude,
      frame.longitude,
    );

    return distance >= _kMinDistanceMeters;
  }

  void _updateLastSent(LocationFrame frame) {
    _lastSentLat = frame.latitude;
    _lastSentLng = frame.longitude;
    _lastSentState = frame.trackingState;
  }

  Future<bool> _trySendToApi(LocationFrame frame) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'location',
        data: frame.toApiJson(),
      );
      final status = response.statusCode ?? 0;
      if (status == 200 || status == 201) {
        dev.log(
          '[LocationRepo] Ubicación enviada — '
          '${frame.latitude}, ${frame.longitude} | ${frame.trackingState}',
          name: 'LocationRepository',
        );
        return true;
      }
      dev.log(
        '[LocationRepo] Servidor rechazó ubicación — status: $status',
        name: 'LocationRepository',
      );
      return false;
    } on DioException catch (e) {
      dev.log(
        '[LocationRepo] DioException al enviar ubicación — ${e.type}: ${e.message}',
        name: 'LocationRepository',
        error: e,
      );
      return false;
    } catch (e, st) {
      dev.log(
        '[LocationRepo] Error inesperado al enviar ubicación: $e',
        name: 'LocationRepository',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<void> _enqueueLocally(LocationFrame frame) async {
    final id = await _localDb.insertLocationFrame(frame.toLocalMap());
    if (id >= 0) {
      dev.log(
        '[LocationRepo] Ubicación encolada offline — id: $id',
        name: 'LocationRepository',
      );
    }
  }

  /// Fórmula de Haversine para calcular distancia en metros entre dos coordenadas.
  double _haversineDistanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double r = 6371000;
    final double dLat = _rad(lat2 - lat1);
    final double dLng = _rad(lng2 - lng1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180;
}

// ── Provider ──────────────────────────────────────────────────────────────────

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(ref);
});
