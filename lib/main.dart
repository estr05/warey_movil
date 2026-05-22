// lib/main.dart
//
// Punto de entrada principal de la aplicación DevUbi.
// Responsabilidad: Orquestar el arranque secuencial estricto, la inspección
// inicial del estado persistido (token Sanctum) y el disparo del hilo de telemetría.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/secure_storage_service.dart';
import 'core/services/background_service.dart';
import 'core/router/app_router.dart';

void main() async {
  // 1. Garantiza la inicialización de los bindings del framework
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Inicializar el ProviderContainer de Riverpod tempranamente
  final container = ProviderContainer();

  // 3. Inspeccionar de forma asíncrona si existe un token Sanctum persistido
  final secureStorage = container.read(secureStorageProvider);
  final token = await secureStorage.readToken();

  // 4. Sincronizar el estado inicial del token en el notifier del GoRouter
  routerNotifier.updateToken(token);

  // 5. Establecer un listener reactivo para mantener al GoRouter sincronizado con los cambios de autenticación
  container.listen<String?>(authStateProvider, (previous, next) {
    routerNotifier.updateToken(next);
  });

  // 6. Inicializar la configuración de FlutterBackgroundService (canales, notificaciones, etc.)
  await BackgroundServiceManager.initializeService();

  // 7. SI EL TOKEN EXISTE: Despertar el hilo de telemetría GPS inmediatamente en background
  if (token != null && token.isNotEmpty) {
    await BackgroundServiceManager.startService();
  }

  // 8. Lanzar la aplicación envolviéndola en el UncontrolledProviderScope usando el container pre-inicializado
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DevUbiApp(),
    ),
  );
}