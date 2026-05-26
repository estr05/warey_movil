// lib/core/network/api_config.dart
//
// Configuración de Entornos de API (Desarrollo y Producción)
// Permite alternar fácilmente entre el servidor local y el servidor de Railway.

import 'package:flutter/foundation.dart';

enum AppEnvironment {
  development,
  production,
}

class ApiConfig {
  /// Entorno activo. Cambia a [AppEnvironment.development] para probar
  /// contra el servidor local. En release build se fuerza producción.
  static const AppEnvironment activeEnvironment = AppEnvironment.production;

  /// URL de desarrollo para EMULADOR Android (10.0.2.2 = localhost del host).
  static const String _devUrl = 'http://10.0.2.2:8000/api/v1/';

  /// URL de desarrollo para DISPOSITIVO FÍSICO (IP local del PC).
  /// Cámbiala a la IP de tu PC en la red local.
  static const String _devPhysicalUrl = 'http://192.168.100.61:8000/api/v1/';

  /// URL de producción alojada en Railway.
  static const String _prodUrl = 'https://werey-production.up.railway.app/api/v1/';

  /// Retorna la URL base correspondiente según el entorno o modo de compilación.
  ///
  /// FLUJO DE DECISIÓN:
  ///   1. Release build → siempre Railway
  ///   2. --dart-define=API_URL=... → URL personalizada
  ///   3. development → _devUrl (emulador). Para físico, cambiar a _devPhysicalUrl
  ///   4. production → Railway
  static String get baseUrl {
    if (kReleaseMode) {
      return _prodUrl;
    }

    const customUrl = String.fromEnvironment('API_URL');
    if (customUrl.isNotEmpty) {
      return customUrl.endsWith('/') ? customUrl : '$customUrl/';
    }

    switch (activeEnvironment) {
      case AppEnvironment.production:
        return _prodUrl;
      case AppEnvironment.development:
        // Para EMULADOR Android (10.0.2.2 = localhost del host)
        return _devUrl;
    }
  }

  static bool get isProduction => baseUrl == _prodUrl;
}