// lib/features/tracking/domain/models/location_frame.dart
//
// Feature: Tracking — Modelo de Frame de Ubicación
//
// Representa una lectura de ubicación GPS lista para ser persistida
// en la cola offline o enviada al backend.
//
// v2: Incluye movementType (STATIC/WALKING/RUNNING/VEHICLE) para:
//   - Enriquecer la reconstrucción de rutas en el backend.
//   - Permitir visualización diferenciada en el mapa (color, grosor).
//   - Habilitar análisis de comportamiento y estadísticas de desplazamiento.
//
// SEPARACIÓN EXPLÍCITA:
//   LocationFrame = datos de ubicación GPS + tipo de movimiento.
//   (La telemetría del dispositivo vive en DeviceStatusFrame).

import 'movement_type.dart';

/// Frame de ubicación GPS del dispositivo.
class LocationFrame {
  final double latitude;
  final double longitude;

  /// Precisión horizontal en metros (del GPS).
  final double? accuracy;

  /// Velocidad en m/s reportada por el GPS (velocidad cruda sin suavizar).
  final double? speedMs;

  /// Velocidad suavizada en m/s (promedio de ventana deslizante del clasificador).
  final double? smoothedSpeedMs;

  /// Altitud en metros sobre el nivel del mar.
  final double? altitude;

  /// Tipo de movimiento clasificado (STATIC/WALKING/RUNNING/VEHICLE).
  final MovementType movementType;

  /// Estado de rastreo en el momento de la captura (SAFE_STATIC, UNSAFE_MOVING, etc.).
  final String trackingState;

  /// true si el dispositivo está dentro de alguna zona segura.
  final bool isInsideSafeZone;

  /// Nombre de la zona segura activa (null si no está en ninguna).
  final String? activeZoneName;

  final double? speedKmh;
  final int? intervaloAplicado;
  final String? motivo;
  final double? bearing;

  /// Timestamp de captura de la ubicación.
  final DateTime capturedAt;

  const LocationFrame({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speedMs,
    this.smoothedSpeedMs,
    this.altitude,
    this.movementType = MovementType.static_,
    required this.trackingState,
    required this.isInsideSafeZone,
    this.activeZoneName,
    this.speedKmh,
    this.intervaloAplicado,
    this.motivo,
    this.bearing,
    required this.capturedAt,
  });

  /// Construye el payload para el endpoint REST de ubicación.
  Map<String, dynamic> toApiJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'speed': speedMs,
        'smoothed_speed': smoothedSpeedMs,
        'altitude': altitude,
        'movement_type': movementType.apiName,
        'tracking_state': trackingState,
        'is_safe_zone': isInsideSafeZone,
        'zone_name': activeZoneName,
        'speed_kmh': speedKmh,
        'intervalo_aplicado': intervaloAplicado,
        'motivo': motivo,
        'bearing': bearing,
        'captured_at': capturedAt.toIso8601String(),
      };

  /// Construye el mapa para persistencia local en SQLite.
  Map<String, dynamic> toLocalMap() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'speed': speedMs,
        'smoothed_speed': smoothedSpeedMs,
        'altitude': altitude,
        'movement_type': movementType.apiName,
        'tracking_state': trackingState,
        'is_safe_zone': isInsideSafeZone ? 1 : 0,
        'zone_name': activeZoneName,
        'speed_kmh': speedKmh,
        'intervalo_aplicado': intervaloAplicado,
        'motivo': motivo,
        'bearing': bearing,
        'captured_at': capturedAt.toIso8601String(),
      };

  /// Reconstruye desde una fila de SQLite.
  factory LocationFrame.fromLocalMap(Map<String, dynamic> map) {
    return LocationFrame(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: map['accuracy'] != null
          ? (map['accuracy'] as num).toDouble()
          : null,
      speedMs:
          map['speed'] != null ? (map['speed'] as num).toDouble() : null,
      smoothedSpeedMs: map['smoothed_speed'] != null
          ? (map['smoothed_speed'] as num).toDouble()
          : null,
      altitude: map['altitude'] != null
          ? (map['altitude'] as num).toDouble()
          : null,
      movementType: MovementTypeX.fromString(map['movement_type'] as String?),
      trackingState: map['tracking_state'] as String? ?? 'UNKNOWN',
      isInsideSafeZone: (map['is_safe_zone'] as int? ?? 0) == 1,
      activeZoneName: map['zone_name'] as String?,
      speedKmh: map['speed_kmh'] != null ? (map['speed_kmh'] as num).toDouble() : null,
      intervaloAplicado: map['intervalo_aplicado'] as int?,
      motivo: map['motivo'] as String?,
      bearing: map['bearing'] != null ? (map['bearing'] as num).toDouble() : null,
      capturedAt: DateTime.parse(map['captured_at'] as String),
    );
  }
}
