// lib/features/tracking/domain/models/geofence_zone.dart
//
// Feature: Tracking — Modelo de Zona Segura (Geofence)
//
// Representa una zona geográfica circular configurada por el servidor.
// El motor de geofencing local evalúa si las coordenadas actuales del
// dispositivo caen dentro del radio de esta zona usando la fórmula de Haversine.

import 'dart:math' as math;

/// Zona geográfica circular que delimita un área segura.
class GeofenceZone {
  /// Identificador único de la zona.
  final String id;

  /// Nombre descriptivo (ej. "Casa", "Oficina", "Escuela").
  final String name;

  /// Latitud del centro de la zona.
  final double latitude;

  /// Longitud del centro de la zona.
  final double longitude;

  /// Radio de la zona en metros.
  final double radiusMeters;

  const GeofenceZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  /// Crea una zona desde un mapa JSON (respuesta del servidor).
  factory GeofenceZone.fromJson(Map<String, dynamic> json) {
    return GeofenceZone(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Zona sin nombre',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radius'] as num).toDouble(),
    );
  }

  /// Serializa la zona a un mapa JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radiusMeters,
      };

  /// Calcula la distancia en metros entre el centro de la zona y
  /// las coordenadas [lat]/[lng] dadas, usando la fórmula de Haversine.
  ///
  /// Esta implementación es local y no requiere plugins externos.
  double distanceTo(double lat, double lng) {
    const double earthRadius = 6371000; // metros

    final double dLat = _toRadians(lat - latitude);
    final double dLng = _toRadians(lng - longitude);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(latitude)) *
            math.cos(_toRadians(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// true si el punto [lat]/[lng] está dentro del radio de la zona.
  bool contains(double lat, double lng) {
    return distanceTo(lat, lng) <= radiusMeters;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  @override
  String toString() =>
      'GeofenceZone(id: $id, name: $name, center: ($latitude, $longitude), radius: ${radiusMeters}m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeofenceZone && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Evento generado cuando el dispositivo entra o sale de una zona.
class GeofenceEvent {
  /// Zona involucrada en el evento.
  final GeofenceZone zone;

  /// true = entró a la zona, false = salió de la zona.
  final bool didEnter;

  /// Timestamp del evento.
  final DateTime timestamp;

  const GeofenceEvent({
    required this.zone,
    required this.didEnter,
    required this.timestamp,
  });

  String get type => didEnter ? 'ENTER' : 'EXIT';

  @override
  String toString() =>
      'GeofenceEvent(type: $type, zone: ${zone.name}, at: $timestamp)';
}
