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
  /// Entorno activo. Apunta a Railway (producción) por defecto.
  /// Cambia a [AppEnvironment.development] para probar contra el servidor local.
  static const AppEnvironment activeEnvironment = AppEnvironment.production;

  /// URL de desarrollo (10.0.2.2 resuelve localhost en el emulador de Android).
  /// Si usas un dispositivo físico, puedes cambiar esto a la IP local de tu PC (ej. http://192.168.1.100:8000/api/v1/).
  static const String _devUrl = 'http://10.0.2.2:8000/api/v1/';

  /// URL de producción alojada en Railway.
  static const String _prodUrl = 'https://werey-production.up.railway.app/api/v1/';

  /// Retorna la URL base correspondiente según el entorno activo o el modo de compilación.
  static String get baseUrl {
    // Si la aplicación está compilada en modo Release (producción final),
    // siempre forzamos el uso de la URL de Railway.
    if (kReleaseMode) {
      return _prodUrl;
    }

    // Permitir sobrescribir la URL mediante argumentos de compilación --dart-define=API_URL=https://...
    const customUrl = String.fromEnvironment('API_URL');
    if (customUrl.isNotEmpty) {
      return customUrl.endsWith('/') ? customUrl : '$customUrl/';
    }

    // De lo contrario, usamos el entorno configurado manualmente arriba
    switch (activeEnvironment) {
      case AppEnvironment.production:
        return _prodUrl;
      case AppEnvironment.development:
        return _devUrl;
    }
  }

  /// Verifica si el entorno actual es Producción.
  static bool get isProduction => baseUrl == _prodUrl;
}
