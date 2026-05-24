// lib/core/services/background_service.dart
//
// Capa Core — Gestor del Servicio en Primer Plano
//
// Android: AndroidForegroundService — sobrevive a la muerte de la UI.
// iOS:     BackgroundFetch / BGProcessingTask — ejecuta en background.
//
// REGLA CRÍTICA: onStart y onIosBackground son funciones TOP-LEVEL
// obligatoriamente. No pueden ser métodos de clase. El isolate del OS
// los llama directamente por nombre mediante @pragma('vm:entry-point').
//
// v2: Usa TrackingEngine en lugar de TelemetryEngine.
//     Centraliza estados, timers, geofencing y sincronización.

import 'dart:developer' as dev;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tracking/domain/engines/tracking_engine.dart';
import '../../features/tracking/domain/services/tracking_sync_service.dart';

// ── Constantes del canal de notificación ─────────────────────────────────────

const String _kChannelId = 'devubi_tracking';
const String _kChannelName = 'DevUbi Node Active';
const String _kChannelDescription = 'Servicio de rastreo activo en primer plano.';
const int _kNotificationId = 888;

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINTS DEL ISOLATE (funciones TOP-LEVEL obligatorias)
// @pragma('vm:entry-point') previene que el tree-shaker elimine estas funciones.
// ─────────────────────────────────────────────────────────────────────────────

/// Entry point de iOS para tareas en background (BGProcessingTask).
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  dev.log('[BgService] iOS background handler invocado.', name: 'BackgroundService');
  return true;
}

/// Entry point principal del isolate de background — Android Foreground + iOS Foreground.
///
/// Corre en un hilo Dart completamente separado de la UI.
/// No tiene acceso al BuildContext, ProviderScope de la UI, ni a widgets.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // 1. Inicializar los bindings de Flutter en este isolate secundario
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Registrar todos los plugins nativos en este isolate
  DartPluginRegistrant.ensureInitialized();

  dev.log('[BgService] Isolate de background iniciado.', name: 'BackgroundService');

  // 3. Actualizar la notificación persistente (Android)
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });

    service.setForegroundNotificationInfo(
      title: _kChannelName,
      content: 'Rastreo inteligente activo...',
    );
  }

  // 4. Crear un ProviderContainer LOCAL para este isolate.
  //    NO se puede usar el ProviderScope de la UI (vive en otro isolate).
  final container = ProviderContainer();

  // 5. Iniciar el TrackingEngine — motor centralizado de rastreo inteligente
  final engine = container.read(trackingEngineProvider);
  engine.start();

  dev.log(
    '[BgService] TrackingEngine iniciado (geofencing + estados dinámicos).',
    name: 'BackgroundService',
  );

  // 6. Escuchar la orden de parada limpia desde la UI
  service.on('stopService').listen((_) {
    dev.log('[BgService] Señal stopService recibida. Deteniendo engine...', name: 'BackgroundService');
    engine.stop();
    container.dispose();
    service.stopSelf();
    dev.log('[BgService] Isolate terminado correctamente.', name: 'BackgroundService');
  });

  // 7. Escuchar actualizaciones de zonas seguras desde la UI
  service.on('updateGeofenceZones').listen((data) {
    // data: { 'zones': [ { 'id', 'name', 'latitude', 'longitude', 'radius' } ] }
    dev.log('[BgService] Actualización de zonas recibida.', name: 'BackgroundService');
    // El TrackingEngine es responsable de parsear y actualizar las zonas.
    // Este canal es el puente entre el isolate de UI y el de background.
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASE GESTORA (corre en el hilo principal / UI)
// ─────────────────────────────────────────────────────────────────────────────

class BackgroundServiceManager {
  BackgroundServiceManager._();

  /// Configura el canal de notificación y el servicio de background.
  /// Debe invocarse una sola vez en main(), ANTES de runApp().
  static Future<void> initializeService() async {
    // ── 1. Canal de notificación persistente (Android 8+) ─────────────────
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: _kChannelDescription,
      importance: Importance.low, // Low para no interrumpir al usuario
      playSound: false,
      enableVibration: false,
    );

    final notificationsPlugin = FlutterLocalNotificationsPlugin();

    await notificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    await notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    dev.log(
      '[BgService] Canal de notificación "$_kChannelId" creado.',
      name: 'BackgroundServiceManager',
    );

    // ── 2. Configurar FlutterBackgroundService ────────────────────────────
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _kChannelId,
        initialNotificationTitle: _kChannelName,
        initialNotificationContent: 'Rastreo inteligente listo...',
        foregroundServiceNotificationId: _kNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    dev.log(
      '[BgService] FlutterBackgroundService configurado (autoStart: false).',
      name: 'BackgroundServiceManager',
    );
  }

  /// Inicia el servicio en primer plano (ej. al vincular el dispositivo).
  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      dev.log('[BgService] Servicio iniciado.', name: 'BackgroundServiceManager');
    } else {
      dev.log('[BgService] El servicio ya estaba en ejecución.', name: 'BackgroundServiceManager');
    }
  }

  /// Detiene el servicio enviando la señal al isolate para cierre limpio.
  static void stopService() {
    FlutterBackgroundService().invoke('stopService');
    dev.log('[BgService] Señal de parada enviada.', name: 'BackgroundServiceManager');
  }

  /// Retorna true si el servicio de background está activo.
  static Future<bool> isRunning() {
    return FlutterBackgroundService().isRunning();
  }
}
