// lib/features/tracking/domain/models/device_status_frame.dart
//
// Feature: Tracking — Modelo de Frame de Estado del Dispositivo
//
// Representa la telemetría del dispositivo (batería, conectividad, señal, etc.)
// que se envía de forma INDEPENDIENTE a la ubicación GPS.
//
// SEPARACIÓN EXPLÍCITA:
//   DeviceStatusFrame = estado del hardware y conectividad.
//   Siempre se envía, independientemente del estado de geofencing.
//   (La ubicación GPS vive en LocationFrame).

/// Tipo de conexión activa del dispositivo.
enum ConnectionType {
  wifi,
  cellular,
  none,
}

/// Frame de estado del dispositivo: batería, conectividad, señal.
class DeviceStatusFrame {
  /// Nivel de batería en porcentaje (0-100).
  final int batteryLevel;

  /// true si el dispositivo está cargando.
  final bool isCharging;

  /// Tipo de conexión de red activa.
  final ConnectionType connectionType;

  /// Intensidad de señal celular (0-4, null si no hay señal celular).
  final int? signalStrength;

  /// true si hay acceso real a internet (no solo red disponible).
  final bool hasInternetAccess;

  /// Estado de rastreo actual del dispositivo.
  final String trackingState;

  /// Actividad general del dispositivo (IDLE, ACTIVE, CHARGING, etc.).
  final String activityStatus;

  /// true si la pantalla del dispositivo estaba encendida al momento de la captura.
  /// null si no se pudo determinar el estado (e.g., primer frame antes de un ciclo de vida).
  final bool? screenActive;

  /// Timestamp de captura.
  final DateTime capturedAt;

  const DeviceStatusFrame({
    required this.batteryLevel,
    required this.isCharging,
    required this.connectionType,
    this.signalStrength,
    required this.hasInternetAccess,
    required this.trackingState,
    required this.activityStatus,
    this.screenActive,
    required this.capturedAt,
  });

  /// Devuelve una copia del frame con los campos indicados sobreescritos.
  DeviceStatusFrame copyWith({
    int? batteryLevel,
    bool? isCharging,
    ConnectionType? connectionType,
    int? signalStrength,
    bool? hasInternetAccess,
    String? trackingState,
    String? activityStatus,
    bool? screenActive,
    DateTime? capturedAt,
  }) {
    return DeviceStatusFrame(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      connectionType: connectionType ?? this.connectionType,
      signalStrength: signalStrength ?? this.signalStrength,
      hasInternetAccess: hasInternetAccess ?? this.hasInternetAccess,
      trackingState: trackingState ?? this.trackingState,
      activityStatus: activityStatus ?? this.activityStatus,
      screenActive: screenActive ?? this.screenActive,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }

  /// Construye el payload para el endpoint REST de telemetría.
  Map<String, dynamic> toApiJson() => {
        'battery_level': batteryLevel,
        'is_charging': isCharging,
        'connection_type': connectionType.name,
        'signal_strength': signalStrength,
        'has_internet': hasInternetAccess,
        'tracking_state': trackingState,
        'activity_status': activityStatus,
        'screen_active': screenActive,
        'captured_at': capturedAt.toIso8601String(),
      };

  /// Construye el mapa para persistencia local en SQLite.
  /// SQLite no soporta BOOLEAN nativo: se serializa screenActive como 0/1/-1.
  /// -1 representa null (estado desconocido).
  Map<String, dynamic> toLocalMap() => {
        'battery_level': batteryLevel,
        'is_charging': isCharging ? 1 : 0,
        'connection_type': connectionType.name,
        'signal_strength': signalStrength,
        'has_internet': hasInternetAccess ? 1 : 0,
        'tracking_state': trackingState,
        'activity_status': activityStatus,
        'screen_active': screenActive == null ? -1 : (screenActive! ? 1 : 0),
        'captured_at': capturedAt.toIso8601String(),
      };

  /// Reconstruye desde una fila de SQLite.
  /// El valor -1 en 'screen_active' representa null (estado desconocido).
  factory DeviceStatusFrame.fromLocalMap(Map<String, dynamic> map) {
    final rawScreen = map['screen_active'] as int?;
    return DeviceStatusFrame(
      batteryLevel: map['battery_level'] as int? ?? 0,
      isCharging: (map['is_charging'] as int? ?? 0) == 1,
      connectionType: _parseConnectionType(map['connection_type'] as String?),
      signalStrength: map['signal_strength'] as int?,
      hasInternetAccess: (map['has_internet'] as int? ?? 0) == 1,
      trackingState: map['tracking_state'] as String? ?? 'UNKNOWN',
      activityStatus: map['activity_status'] as String? ?? 'UNKNOWN',
      screenActive: rawScreen == null || rawScreen == -1 ? null : rawScreen == 1,
      capturedAt: DateTime.parse(map['captured_at'] as String),
    );
  }

  static ConnectionType _parseConnectionType(String? raw) {
    switch (raw) {
      case 'wifi':
        return ConnectionType.wifi;
      case 'cellular':
        return ConnectionType.cellular;
      default:
        return ConnectionType.none;
    }
  }
}
