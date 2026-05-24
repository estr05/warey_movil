// lib/features/telemetry/data/repositories/telemetry_repository_impl.dart
//
// Feature: Telemetry — Capa Data (Repositorio)
// Responsabilidad: Decidir si un frame de telemetría se envía en tiempo real
// al backend (online) o se encola localmente (offline/fallback).
//
// Flujo de decisión:
//   1. Verificar ConnectivityResult.
//   2. Si hay red → POST /telemetry → si falla → fallback a BD local.
//   3. Si no hay red → directamente a BD local.
//
// Esta clase NO contiene lógica de UI ni accede a ningún widget.

import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/services/local_database_service.dart';

class TelemetryRepositoryImpl {
  final Ref _ref;

  // Acceso lazy a los providers para evitar dependencias circulares.
  Dio get _dio => _ref.read(dioProvider);
  LocalDatabaseService get _localDb => _ref.read(localDatabaseProvider);

  const TelemetryRepositoryImpl(this._ref);

  // ── API Pública ─────────────────────────────────────────────────────────────

  /// Procesa un frame de telemetría: lo envía online o lo encola offline.
  ///
  /// Parámetros:
  /// - [lat] / [lng]: Coordenadas GPS del dispositivo.
  /// - [battery]: Nivel de batería (0–100).
  /// - [isCharging]: Si el dispositivo está cargando en este momento.
  /// - [connectionType]: Tipo de conexión activa ("wifi", "cellular", "none").
  Future<void> processTelemetryFrame({
    required double lat,
    required double lng,
    required int battery,
    required bool isCharging,
    required String connectionType,
  }) async {
    final payload = _buildPayload(
      lat: lat,
      lng: lng,
      battery: battery,
      isCharging: isCharging,
      connectionType: connectionType,
    );

    // Evaluar conectividad actual en el momento exacto de la llamada
    final connectivityResults = await Connectivity().checkConnectivity();
    final isOnline = _hasActiveConnection(connectivityResults);

    if (isOnline) {
      final sent = await _trySendToApi(payload);
      if (sent) return; // Éxito: no es necesario guardar localmente
    }

    // Offline o la API falló: persiste localmente
    await _saveToLocalQueue(payload);
  }

  // ── Helpers privados ────────────────────────────────────────────────────────

  /// Construye el mapa de payload estándar del contrato DevUbi.
  Map<String, dynamic> _buildPayload({
    required double lat,
    required double lng,
    required int battery,
    required bool isCharging,
    required String connectionType,
  }) {
    return {
      'latitude': lat,
      'longitude': lng,
      'battery_level': battery,
      'is_charging': isCharging ? 1 : 0, // SQLite no tiene BOOLEAN nativo
      'connection_type': connectionType,
      'captured_at': DateTime.now().toIso8601String(),
    };
  }

  /// [true] si hay al menos una conexión activa (Wi-Fi o Cellular).
  bool _hasActiveConnection(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi || r == ConnectivityResult.mobile);
  }

  /// Intenta enviar el frame a la API REST del backend.
  ///
  /// Retorna [true] si el servidor confirmó con HTTP 200 o 201.
  /// Retorna [false] en cualquier error (timeout, 5xx, red, etc.).
  Future<bool> _trySendToApi(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'telemetry',
        data: {
          'latitude': payload['latitude'],
          'longitude': payload['longitude'],
          'battery_level': payload['battery_level'],
          // El backend espera boolean real, no 0/1
          'is_charging': (payload['is_charging'] as int) == 1,
          'connection_type': payload['connection_type'],
          'captured_at': payload['captured_at'],
        },
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode == 200 || statusCode == 201) {
        dev.log(
          '[TelemetryRepo] Frame enviado online — lat: ${payload['latitude']} lng: ${payload['longitude']}',
          name: 'TelemetryRepositoryImpl',
        );
        return true;
      }

      dev.log(
        '[TelemetryRepo] Respuesta inesperada del servidor: $statusCode. Redirigiendo a cola local.',
        name: 'TelemetryRepositoryImpl',
      );
      return false;
    } on DioException catch (e) {
      dev.log(
        '[TelemetryRepo] DioException al enviar frame — ${e.type}: ${e.message}. Redirigiendo a cola local.',
        name: 'TelemetryRepositoryImpl',
        error: e,
      );
      return false;
    } catch (e, st) {
      dev.log(
        '[TelemetryRepo] Error inesperado al enviar frame: $e',
        name: 'TelemetryRepositoryImpl',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Persiste el frame en la base de datos SQLite local.
  Future<void> _saveToLocalQueue(Map<String, dynamic> payload) async {
    final id = await _localDb.insertFrame(payload);
    if (id >= 0) {
      dev.log(
        '[TelemetryRepo] Frame encolado localmente — id: $id',
        name: 'TelemetryRepositoryImpl',
      );
    } else {
      dev.log(
        '[TelemetryRepo] ADVERTENCIA: Fallo al insertar frame en cola local.',
        name: 'TelemetryRepositoryImpl',
      );
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final telemetryRepositoryProvider = Provider<TelemetryRepositoryImpl>((ref) {
  return TelemetryRepositoryImpl(ref);
});
