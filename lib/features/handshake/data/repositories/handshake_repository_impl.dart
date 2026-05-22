// lib/features/handshake/data/repositories/handshake_repository_impl.dart
//
// Feature: Handshake — Capa Data (Implementación del Repositorio)
// Orquesta el DataSource remoto y el almacenamiento seguro.
// Si la vinculación es exitosa, guarda el token antes de notificar el éxito.
// Traduce las excepciones de Dio a HandshakeFailure con mensajes legibles.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/handshake_repository.dart';
import '../datasources/handshake_remote_datasource.dart';
import '../../../../core/services/secure_storage_service.dart';

class HandshakeRepositoryImpl implements HandshakeRepository {
  final HandshakeRemoteDataSource _dataSource;
  final SecureStorageService _secureStorage;

  const HandshakeRepositoryImpl({
    required HandshakeRemoteDataSource dataSource,
    required SecureStorageService secureStorage,
  })  : _dataSource = dataSource,
        _secureStorage = secureStorage;

  @override
  Future<HandshakeResult> validatePairingCode({
    required String code,
    required String deviceUuid,
  }) async {
    try {
      final responseData = await _dataSource.validatePairingCode(
        code: code,
        uuid: deviceUuid,
      );

      // Persiste el token de Sanctum ANTES de reportar éxito.
      // Si este paso falla, el usuario tendrá que volver a vincular.
      await _secureStorage.saveToken(responseData.token);

      return const HandshakeSuccess();
    } on DioException catch (e) {
      return HandshakeFailure(_parseDioError(e));
    } catch (e) {
      return HandshakeFailure('Error inesperado: ${e.runtimeType}');
    }
  }

  // ── Helpers privados ─────────────────────────────────────────────────────────

  /// Traduce un [DioException] a un mensaje legible para el usuario.
  String _parseDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'El servidor tardó demasiado en responder. Verifica tu conexión.';
      case DioExceptionType.connectionError:
        return 'No se pudo conectar al servidor. Verifica que estés en la red correcta.';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final serverMessage = e.response?.data?['message'] as String?;

        if (statusCode == 404) {
          return 'Código de emparejamiento no encontrado o expirado.';
        }
        if (statusCode == 422) {
          return serverMessage ?? 'El código introducido no tiene el formato correcto.';
        }
        if (statusCode == 409) {
          return 'Este dispositivo ya está vinculado a otra cuenta.';
        }
        return serverMessage ?? 'Error del servidor ($statusCode). Intenta de nuevo.';
      default:
        return e.message ?? 'Ocurrió un error de red desconocido.';
    }
  }
}

/// Provider del repositorio de Handshake.
/// La UI nunca debe importar HandshakeRepositoryImpl directamente.
final handshakeRepositoryProvider = Provider<HandshakeRepository>((ref) {
  return HandshakeRepositoryImpl(
    dataSource: ref.watch(handshakeRemoteDataSourceProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
});
