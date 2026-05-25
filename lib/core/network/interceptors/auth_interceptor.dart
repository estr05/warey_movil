// lib/core/network/interceptors/auth_interceptor.dart
//
// Capa Core - Interceptor de Autenticacion y Seguridad
// Inyecta Bearer token y reacciona globalmente a revocaciones 401.

import 'package:dio/dio.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router/app_router.dart';
import '../../security/session_notice_provider.dart';
import '../../services/secure_storage_service.dart';

class AuthInterceptor extends Interceptor {
  final Ref _ref;

  AuthInterceptor(this._ref);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
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
    if (err.response?.statusCode == 401) {
      try {
        final message =
            _extractMessage(err.response?.data) ??
            'La sesion fue revocada por el backend. Vincula el telefono nuevamente.';

        // El backend decide la revocacion; Flutter solo apaga tracking y
        // devuelve al usuario al flujo de pairing.
        FlutterBackgroundService().invoke('stopService');
        await _ref.read(authStateProvider.notifier).deleteToken();
        _ref.read(sessionNoticeProvider.notifier).showRevoked(message);
      } catch (_) {
        // En background puede no existir el mismo arbol de providers de UI.
      }
    }

    return handler.next(err);
  }

  String? _extractMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final message = data['message'] ?? data['error'];
      return message?.toString();
    }
    if (data is Map) {
      final message = data['message'] ?? data['error'];
      return message?.toString();
    }
    return null;
  }
}
