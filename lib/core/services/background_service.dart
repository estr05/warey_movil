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

import 'dart:developer' as dev;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/telemetry/domain/engines/telemetry_engine.dart';

// ── Constantes del canal de notificación ─────────────────────────────────────

const String _kChannelId = 'devubi_telemetry';
const String _kChannelName = 'DevUbi Node Active';
const String _kChannelDescription = 'Servicio de telemetría activo en primer plano.';
const int _kNotificationId = 888;

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINTS DEL ISOLATE (deben ser funciones TOP-LEVEL)
// @pragma('vm:entry-point') previene que el tree-shaker elimine estas funciones
// ya que el linker no puede trazar su referencia en el manifest nativo.
// ─────────────────────────────────────────────────────────────────────────────

/// Entry point de iOS para tareas en background (BGProcessingTask).
/// Debe retornar true para indicar que el sistema puede mantener la app viva.
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  dev.log('[BgService] iOS background handler invocado.', name: 'BackgroundService');
  return true;
}

/// Entry point principal del isolate de background — Android Foreground + iOS Foreground.
///
/// Este método corre en un hilo Dart completamente separado de la UI.
/// No tiene acceso al BuildContext, ProviderScope de la UI, ni a widgets.
/// Debe inicializar sus propias instancias de plugins y providers.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // 1. Inicializar el binding de Flutter en este isolate secundario
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Registrar todos los plugins nativos en este nuevo isolate
  //    Sin esto, sqflite, secure_storage, etc. no funcionan aquí.
  DartPluginRegistrant.ensureInitialized();

  dev.log('[BgService] Isolate de background iniciado.', name: 'BackgroundService');

  // 3. Actualizar el contenido de la notificación persistente (Android)
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });

    service.setForegroundNotificationInfo(
      title: _kChannelName,
      content: 'Transmitiendo telemetría...',
    );
  }

  // 4. Crear un ProviderContainer LOCAL para este isolate.
  //    NO se puede usar el ProviderScope de la UI (vive en otro isolate).
  //    Este container tiene acceso a los mismos providers stateless (Dio, SQLite, etc.)
  final container = ProviderContainer();

  // 5. Leer el TelemetryEngine e iniciar el loop de captura periódica
  final engine = container.read(telemetryEngineProvider);
  engine.start();

  dev.log('[BgService] TelemetryEngine arrancado dentro del isolate.', name: 'BackgroundService');

  // 6. Escuchar la orden de parada limpia desde la UI
  service.on('stopService').listen((_) {
    dev.log('[BgService] Señal stopService recibida. Deteniendo engine...', name: 'BackgroundService');
    engine.stop();
    container.dispose();
    service.stopSelf();
    dev.log('[BgService] Isolate terminado correctamente.', name: 'BackgroundService');
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

    dev.log('[BgService] Canal de notificación "$_kChannelId" creado.', name: 'BackgroundServiceManager');

    // ── 2. Configurar FlutterBackgroundService ────────────────────────────
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _kChannelId,
        initialNotificationTitle: _kChannelName,
        initialNotificationContent: 'Listo para transmitir...',
        foregroundServiceNotificationId: _kNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    dev.log('[BgService] FlutterBackgroundService configurado (autoStart: false).', name: 'BackgroundServiceManager');
  }

  /// Inicia el servicio en primer plano desde la UI (ej. al vincular el dispositivo).
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

  /// Detiene el servicio enviando la señal al isolate para un cierre limpio.
  static void stopService() {
    FlutterBackgroundService().invoke('stopService');
    dev.log('[BgService] Señal de parada enviada.', name: 'BackgroundServiceManager');
  }

  /// Retorna true si el servicio de background está activo.
  static Future<bool> isRunning() {
    return FlutterBackgroundService().isRunning();
  }
}
