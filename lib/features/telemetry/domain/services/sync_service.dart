// lib/features/telemetry/domain/services/sync_service.dart
//
// Feature: Telemetry — Capa Domain (Servicio de Sincronización)
// Responsabilidad: escuchar el stream de conectividad y, cuando la red se
// recupera, drenar la cola offline de SQLite hacia el backend en orden FIFO,
// eliminando cada frame con confirmación HTTP 200/201 explícita.
//
// Ciclo de vida del servicio:
//   - Se inicializa al leer `syncServiceProvider` (ej. en main.dart o al
//     activar la sesión del usuario).
//   - Escucha cambios de red de forma continua mientras vive el Provider.
//   - Se cancela automáticamente al destruirse el Provider (ref.onDispose).
//
// Garantías de integridad:
//   - FIFO: los frames se envían en orden de inserción (id ASC).
//   - Sin duplicados: deleteFrames solo se llama tras HTTP 200/201 confirmado.
//   - Sin lock: un frame corrupto o con error es saltado (logged) para no
//     bloquear la sincronización del resto de la cola.
//   - Sin re-entradas: una sincronización en curso impide lanzar otra.

import 'dart:async';
import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/services/local_database_service.dart';

class SyncService {
  final Ref _ref;

  Dio get _dio => _ref.read(dioProvider);
  LocalDatabaseService get _localDb => _ref.read(localDatabaseProvider);

  // Suscripción al stream de conectividad
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Guard de re-entradas: evita lanzar múltiples sincronizaciones simultáneas
  bool _isSyncing = false;

  SyncService(this._ref);

  // ── Ciclo de Vida ──────────────────────────────────────────────────────────

  /// Inicia el listener reactivo sobre el stream de conectividad.
  /// Debe invocarse una sola vez al inicializar el servicio.
  void initialize() {
    dev.log(
      '[SyncService] Iniciando listener de conectividad...',
      name: 'SyncService',
    );

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged, onError: _onStreamError);
  }

  /// Cancela la suscripción y libera recursos.
  /// Invocado automáticamente por ref.onDispose en el Provider.
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    dev.log('[SyncService] Listener de conectividad cancelado.', name: 'SyncService');
  }

  // ── Lógica de Sincronización ───────────────────────────────────────────────

  /// Manejador de cambios en el estado de la red.
  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final isOnline = results.any((r) =>
        r == ConnectivityResult.wifi || r == ConnectivityResult.mobile);

    dev.log(
      '[SyncService] Cambio de conectividad detectado — online: $isOnline | tipos: ${results.map((r) => r.name).join(", ")}',
      name: 'SyncService',
    );

    if (!isOnline) return; // Sin red: nada que sincronizar

    await _drainOfflineQueue();
  }

  /// Drena la cola offline completa en orden FIFO.
  ///
  /// Cada frame es enviado individualmente para garantizar confirmación
  /// explícita antes de eliminarlo. Un error en un frame no detiene al resto.
  Future<void> _drainOfflineQueue() async {
    // Guard de re-entrada
    if (_isSyncing) {
      dev.log(
        '[SyncService] Sincronización ya en curso — omitiendo nueva solicitud.',
        name: 'SyncService',
      );
      return;
    }

    _isSyncing = true;
    dev.log('[SyncService] Iniciando drenaje de la cola offline...', name: 'SyncService');

    try {
      final pendingFrames = await _localDb.getPendingFrames();

      if (pendingFrames.isEmpty) {
        dev.log('[SyncService] Cola offline vacía. Nada que sincronizar.', name: 'SyncService');
        return;
      }

      dev.log(
        '[SyncService] ${pendingFrames.length} frame(s) en cola. Iniciando sincronización FIFO...',
        name: 'SyncService',
      );

      int successCount = 0;
      int failCount = 0;

      // Iterar en orden FIFO (los frames ya vienen ordenados por id ASC desde getPendingFrames)
      for (final frame in pendingFrames) {
        final frameId = _extractId(frame);
        if (frameId == null) {
          dev.log(
            '[SyncService] Frame con id nulo o inválido — saltando: $frame',
            name: 'SyncService',
          );
          failCount++;
          continue;
        }

        final success = await _uploadFrame(frame, frameId);
        if (success) {
          successCount++;
        } else {
          failCount++;
          // Continuar con el siguiente frame: no bloquear la cola por un error individual
        }
      }

      dev.log(
        '[SyncService] Sincronización completada — ✓ $successCount enviado(s) | ✗ $failCount fallido(s)',
        name: 'SyncService',
      );
    } catch (e, st) {
      dev.log(
        '[SyncService] ERROR CRÍTICO durante el drenaje de la cola: $e',
        name: 'SyncService',
        error: e,
        stackTrace: st,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Sube un único frame al backend y lo elimina de la BD si tiene éxito.
  ///
  /// Retorna [true] si el frame fue enviado y eliminado correctamente.
  /// Retorna [false] si el frame es corrupto, tiene error de red o el servidor
  /// responde con un código de error. En ese caso el frame permanece en la BD.
  Future<bool> _uploadFrame(Map<String, dynamic> frame, int frameId) async {
    // Validar y extraer campos requeridos antes de intentar enviar
    final payload = _extractPayload(frame, frameId);
    if (payload == null) return false; // Frame corrupto: loggear y saltar

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'telemetry',
        data: payload,
      );

      final statusCode = response.statusCode ?? 0;

      if (statusCode == 200 || statusCode == 201) {
        // Confirmación explícita del backend: es seguro eliminar el frame
        await _localDb.deleteFrames([frameId]);
        dev.log(
          '[SyncService] Frame #$frameId sincronizado y eliminado — status: $statusCode',
          name: 'SyncService',
        );
        return true;
      } else {
        dev.log(
          '[SyncService] Frame #$frameId rechazado por el servidor — status: $statusCode. El frame permanece en cola.',
          name: 'SyncService',
        );
        return false;
      }
    } on DioException catch (e) {
      // Errores de red (timeout, sin conexión) son recuperables: el frame permanece
      dev.log(
        '[SyncService] Frame #$frameId — DioException: ${e.type} | ${e.message}',
        name: 'SyncService',
        error: e,
      );
      return false;
    } catch (e, st) {
      // Errores inesperados: el frame permanece para no perder datos
      dev.log(
        '[SyncService] Frame #$frameId — Error inesperado: $e',
        name: 'SyncService',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  // ── Helpers de Validación ──────────────────────────────────────────────────

  /// Extrae el `id` del frame de forma segura, retorna null si es inválido.
  int? _extractId(Map<String, dynamic> frame) {
    final rawId = frame[LocalDatabaseService.colId];
    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    return null;
  }

  /// Construye el payload para la API a partir de una fila de SQLite.
  ///
  /// Valida cada campo crítico. Si algún campo está ausente o tiene un tipo
  /// incorrecto, logea el frame corrupto y retorna null para saltar el envío.
  Map<String, dynamic>? _extractPayload(Map<String, dynamic> frame, int frameId) {
    try {
      final latitude = frame[LocalDatabaseService.colLatitude];
      final longitude = frame[LocalDatabaseService.colLongitude];
      final batteryLevel = frame[LocalDatabaseService.colBatteryLevel];
      final isChargingRaw = frame[LocalDatabaseService.colIsCharging];
      final connectionType = frame[LocalDatabaseService.colConnectionType];
      final createdAt = frame[LocalDatabaseService.colCreatedAt];

      // Validar que todos los campos críticos existen y tienen tipos correctos
      if (latitude is! num ||
          longitude is! num ||
          batteryLevel is! int ||
          isChargingRaw is! int ||
          connectionType is! String ||
          createdAt is! String) {
        dev.log(
          '[SyncService] Frame #$frameId CORRUPTO — tipos inválidos: $frame',
          name: 'SyncService',
        );
        return null;
      }

      return {
        'latitude': latitude.toDouble(),
        'longitude': longitude.toDouble(),
        'battery_level': batteryLevel,
        'is_charging': isChargingRaw == 1, // Convertir int → boolean para la API REST
        'connection_type': connectionType,
        'created_at': createdAt,
      };
    } catch (e) {
      dev.log(
        '[SyncService] Frame #$frameId — Excepción al extraer payload: $e',
        name: 'SyncService',
        error: e,
      );
      return null;
    }
  }

  /// Maneja errores del stream de conectividad (raramente ocurren).
  void _onStreamError(Object error, StackTrace st) {
    dev.log(
      '[SyncService] ERROR en el stream de conectividad: $error',
      name: 'SyncService',
      error: error,
      stackTrace: st,
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

/// Provider global del SyncService.
///
/// Al leerse, inicializa el listener de conectividad automáticamente.
/// Al destruirse el árbol de providers, cancela la suscripción limpiamente.
///
/// Uso recomendado: leer este provider en un widget raíz o en el initState
/// de la sesión del usuario para activar el motor de sincronización:
///
/// ```dart
/// ref.read(syncServiceProvider); // Activar el engine
/// ```
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref);

  // Iniciar el listener reactivo al crear el Provider
  service.initialize();

  // Garantizar la cancelación del stream al destruirse el Provider
  ref.onDispose(service.dispose);

  return service;
});
