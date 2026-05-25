// lib/features/tracking/domain/services/geofence_service.dart
//
// Feature: Tracking — Servicio de Geofencing Local
//
// Responsabilidades:
//   1. Mantener la lista de zonas seguras configuradas.
//   2. Evaluar si las coordenadas actuales caen en alguna zona.
//   3. Detectar eventos de ENTRADA y SALIDA emitiendo un Stream de GeofenceEvent.
//   4. Los cambios de zona generan eventos inmediatos para activar sincronización.
//
// Toda la lógica corre localmente en el dispositivo sin llamadas de red.
// Las zonas se cargan desde el backend al iniciar sesión y se persisten
// localmente para funcionar sin conexión.

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/safe_place_repository.dart';
import '../models/geofence_zone.dart';

class GeofenceService {
  // ── Estado interno ──────────────────────────────────────────────────────────

  /// Zonas seguras actualmente configuradas.
  List<GeofenceZone> _zones = [];

  /// Zona en la que el dispositivo estaba en la última evaluación.
  /// null si el dispositivo estaba fuera de todas las zonas.
  GeofenceZone? _currentZone;

  /// Controller del stream de eventos de geofencing.
  final StreamController<GeofenceEvent> _eventController =
      StreamController<GeofenceEvent>.broadcast();

  // ── API Pública ─────────────────────────────────────────────────────────────

  /// Stream de eventos de entrada/salida de zonas.
  /// Los suscriptores reciben eventos inmediatos ante cambios de zona.
  Stream<GeofenceEvent> get events => _eventController.stream;

  /// Zona actual en la que se encuentra el dispositivo.
  /// null si está fuera de todas las zonas seguras.
  GeofenceZone? get currentZone => _currentZone;

  /// true si el dispositivo está actualmente dentro de alguna zona segura.
  bool get isInsideSafeZone => _currentZone != null;

  /// Lista de zonas actualmente configuradas.
  List<GeofenceZone> get zones => List.unmodifiable(_zones);

  /// Reemplaza todas las zonas con la lista actualizada del servidor.
  ///
  /// Se llama al iniciar sesión o al sincronizar configuración del backend.
  /// Re-evalúa la posición actual inmediatamente si se proporcionan coordenadas.
  void updateZones(
    List<GeofenceZone> newZones, {
    double? currentLat,
    double? currentLng,
  }) {
    _zones = List.from(newZones);
    dev.log(
      '[GeofenceService] ${_zones.length} zona(s) configurada(s): '
      '${_zones.map((z) => z.name).join(', ')}',
      name: 'GeofenceService',
    );

    // Re-evaluar posición actual con las nuevas zonas
    if (currentLat != null && currentLng != null) {
      _evaluate(currentLat, currentLng);
    }
  }

  /// Sincroniza zonas con el backend.
  Future<void> syncFromBackend(SafePlaceRepository repo) async {
    try {
      final zones = await repo.fetchSafePlaces();
      updateZones(zones);
      dev.log('[GeofenceService] Zonas sincronizadas: ${zones.length}', name: 'GeofenceService');
    } catch (e) {
      dev.log('[GeofenceService] Error sincronizando zonas: $e', name: 'GeofenceService');
      // Si falla, mantener las zonas locales (si las hay)
    }
  }

  /// Agrega o actualiza una zona individual sin reemplazar toda la lista.
  void upsertZone(GeofenceZone zone) {
    final idx = _zones.indexWhere((z) => z.id == zone.id);
    if (idx >= 0) {
      _zones[idx] = zone;
    } else {
      _zones.add(zone);
    }
    dev.log(
      '[GeofenceService] Zona "${zone.name}" actualizada.',
      name: 'GeofenceService',
    );
  }

  /// Elimina una zona por su ID.
  void removeZone(String zoneId) {
    _zones.removeWhere((z) => z.id == zoneId);
    // Si el dispositivo estaba en esa zona, resetear
    if (_currentZone?.id == zoneId) {
      _currentZone = null;
    }
  }

  /// Evalúa las coordenadas actuales contra todas las zonas.
  ///
  /// Si se detecta un cambio (entrada o salida de zona), emite un [GeofenceEvent]
  /// inmediatamente. Retorna true si el dispositivo está dentro de alguna zona.
  ///
  /// Llamar con cada lectura GPS del dispositivo.
  bool evaluate(double lat, double lng) {
    return _evaluate(lat, lng);
  }

  /// Libera recursos del stream controller.
  void dispose() {
    _eventController.close();
  }

  // ── Lógica interna de evaluación ────────────────────────────────────────────

  bool _evaluate(double lat, double lng) {
    // Buscar la primera zona que contenga las coordenadas actuales
    // (Si hay zonas superpuestas, la prioridad es la primera configurada)
    GeofenceZone? detectedZone;
    for (final zone in _zones) {
      if (zone.contains(lat, lng)) {
        detectedZone = zone;
        break;
      }
    }

    final previousZone = _currentZone;
    _currentZone = detectedZone;

    // ── Detectar cambio de zona ─────────────────────────────────────────────

    if (detectedZone != null && previousZone?.id != detectedZone.id) {
      // Entró a una nueva zona (o es la primera evaluación dentro de una zona)
      final event = GeofenceEvent(
        zone: detectedZone,
        didEnter: true,
        timestamp: DateTime.now(),
      );
      _eventController.add(event);
      dev.log(
        '[GeofenceService] ▶ ENTRADA en zona "${detectedZone.name}" '
        '(dist: ${detectedZone.distanceTo(lat, lng).toStringAsFixed(0)}m / ${detectedZone.radiusMeters}m)',
        name: 'GeofenceService',
      );
    } else if (detectedZone == null && previousZone != null) {
      // Salió de la zona anterior
      final event = GeofenceEvent(
        zone: previousZone,
        didEnter: false,
        timestamp: DateTime.now(),
      );
      _eventController.add(event);
      dev.log(
        '[GeofenceService] ◀ SALIDA de zona "${previousZone.name}"',
        name: 'GeofenceService',
      );
    }

    return _currentZone != null;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final geofenceServiceProvider = Provider<GeofenceService>((ref) {
  final service = GeofenceService();
  ref.onDispose(service.dispose);
  return service;
});
