// lib/core/router/app_router.dart
//
// Capa Core — Configuración de Rutas y Guardia de Estado Reactivo
// Define el enrutador central y la protección de accesos basados en token.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/handshake/presentation/pages/handshake_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../services/secure_storage_service.dart';

/// Rutas nombradas de la aplicación.
abstract final class AppRoutes {
  static const String handshake = '/handshake';
  static const String dashboard = '/dashboard';
}

/// Estado de autenticación reactivo.
/// Permite escuchar de manera unificada el estado del token Sanctum de la app.
final authStateProvider = StateNotifierProvider<AuthStateNotifier, String?>((ref) {
  return AuthStateNotifier(ref.watch(secureStorageProvider));
});

class AuthStateNotifier extends StateNotifier<String?> {
  final SecureStorageService _secureStorage;

  AuthStateNotifier(this._secureStorage) : super(null) {
    checkToken();
  }

  /// Verifica si existe un token almacenado e inicializa el estado.
  Future<void> checkToken() async {
    final token = await _secureStorage.readToken();
    state = token;
  }

  /// Actualiza manualmente el token en el estado (por ejemplo, tras vincular).
  void updateToken(String? token) {
    state = token;
  }

  /// Elimina el token del almacenamiento seguro y limpia el estado.
  Future<void> deleteToken() async {
    await _secureStorage.deleteToken();
    state = null;
  }
}

/// Notificador de cambios para GoRouter.
/// Traduce los cambios de estado del provider de Riverpod a eventos de ChangeNotifier
/// que GoRouter puede usar mediante su propiedad `refreshListenable`.
final routerNotifier = RouterNotifier();

class RouterNotifier extends ChangeNotifier {
  String? _token;
  String? get token => _token;

  void updateToken(String? value) {
    if (_token != value) {
      _token = value;
      notifyListeners();
    }
  }
}

/// Instancia de GoRouter con protección reactiva (Router State Guard).
final GoRouter appRouter = GoRouter(
  debugLogDiagnostics: true,
  initialLocation: AppRoutes.handshake,
  refreshListenable: routerNotifier,
  redirect: (BuildContext context, GoRouterState state) {
    final token = routerNotifier.token;
    
    // Rutas actuales
    final location = state.matchedLocation;
    final isHandshake = location == AppRoutes.handshake || location == '/';

    if (token != null && token.isNotEmpty) {
      // SI EL TOKEN EXISTE: Forzar redirección al Dashboard si está en Handshake
      if (isHandshake) {
        return AppRoutes.dashboard;
      }
    } else {
      // SI EL TOKEN NO EXISTE: Forzar redirección al Handshake si intenta ir a otra parte
      if (!isHandshake) {
        return AppRoutes.handshake;
      }
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      redirect: (context, state) => AppRoutes.handshake,
    ),
    GoRoute(
      path: AppRoutes.handshake,
      name: 'handshake',
      builder: (BuildContext context, GoRouterState state) {
        return const HandshakePage();
      },
    ),
    GoRoute(
      path: AppRoutes.dashboard,
      name: 'dashboard',
      builder: (BuildContext context, GoRouterState state) {
        return const DashboardPage();
      },
    ),
  ],
);
