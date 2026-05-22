// lib/core/network/interceptors/auth_interceptor.dart
//
// Capa Core — Interceptor de Autenticación y Seguridad
// Responsabilidad: Inyectar el token Bearer en cada petición saliente
// y manejar de forma global los errores 401 (No Autorizado), forzando
// la limpieza del token y redirección a HandshakePage.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/secure_storage_service.dart';
import '../../router/app_router.dart';

class AuthInterceptor extends Interceptor {
  final Ref _ref;

  AuthInterceptor(this._ref);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Intentar leer el token del almacenamiento seguro
    final secureStorage = _ref.read(secureStorageProvider);
    final token = await secureStorage.readToken();

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Si la respuesta del servidor es 401 (No Autorizado), el token expiró o fue revocado
    if (err.response?.statusCode == 401) {
      try {
        // Borrar el token reactivamente. 
        // Si estamos en el UI isolate, esto activará el Router Guard y redirigirá al Handshake.
        // Si estamos en el background isolate, simplemente borrará la persistencia.
        await _ref.read(authStateProvider.notifier).deleteToken();
      } catch (e) {
        // Manejo silencioso en caso de error de riverpod
      }
    }

    return handler.next(err);
  }
}
