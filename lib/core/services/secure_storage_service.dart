// lib/core/services/secure_storage_service.dart
//
// Capa Core — Servicio de Almacenamiento Seguro
// Responsabilidad: Guardar, leer y eliminar de forma cifrada el token de autenticación.
// Utiliza flutter_secure_storage para garantizar la persistencia segura.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const String _tokenKey = 'auth_token';
  static const String _deviceUuidKey = 'device_uuid';

  /// Guarda el token de autenticación de forma segura.
  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Lee el token de autenticación guardado. Retorna null si no existe.
  Future<String?> readToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Elimina el token de autenticación guardado.
  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  /// Guarda el UUID estable de esta instalacion.
  Future<void> saveDeviceUuid(String uuid) async {
    await _storage.write(key: _deviceUuidKey, value: uuid);
  }

  /// Lee el UUID estable de esta instalacion. Retorna null si no existe.
  Future<String?> readDeviceUuid() async {
    return await _storage.read(key: _deviceUuidKey);
  }
}

/// Provider de Riverpod para inyectar SecureStorageService en cualquier parte de la app.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
