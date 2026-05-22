// lib/core/network/dio_client.dart
//
// Capa Core — Cliente de Red (Dio Engine)
// Configuración centralizada de Dio con tiempos de espera,
// cabeceras por defecto e interceptores de seguridad.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../services/secure_storage_service.dart';
import 'api_config.dart';
import 'interceptors/auth_interceptor.dart';

/// Provider que expone la instancia configurada de Dio.
/// watch en secureStorageProvider garantiza que si se recrea el almacenamiento seguro,
/// el cliente de red pueda actualizarse de forma reactiva.
final dioProvider = Provider<Dio>((ref) {
  // Observar el secureStorageProvider por si acaso se recrea
  ref.watch(secureStorageProvider);

  final dio = Dio(
    BaseOptions(
      // URL base obtenida dinámicamente según el entorno
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  // Registrar interceptor de autenticación
  dio.interceptors.add(AuthInterceptor(ref));

  // Registrar interceptor de logs en modo desarrollo para facilitar telemetría
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    );
  }

  return dio;
});
