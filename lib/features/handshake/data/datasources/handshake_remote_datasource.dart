// lib/features/handshake/data/datasources/handshake_remote_datasource.dart
//
// Feature: Handshake - Capa Data (Remote DataSource)
// Responsabilidad unica: ejecutar la peticion HTTP al endpoint de vinculacion.
// No decide seguridad ni ownership; eso pertenece al backend.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/services/device_uuid_service.dart';

/// DataSource remoto para el modulo de Handshake.
class HandshakeRemoteDataSource {
  final Dio _dio;

  const HandshakeRemoteDataSource(this._dio);

  /// Envia el codigo, el UUID estable y el fingerprint visual del telefono.
  ///
  /// POST /api/v1/devices/handshake
  /// Body:
  /// {
  ///   "pairing_code": "WRY-XXXX-XXXX",
  ///   "device_uuid": "...",
  ///   "model": "...",
  ///   "manufacturer": "...",
  ///   "android_version": "...",
  ///   "app_version": "...",
  ///   "device_fingerprint": { ... },
  ///   "confirm_replacement": true|false
  /// }
  Future<Map<String, dynamic>> validatePairingCode({
    required String code,
    required DeviceFingerprint fingerprint,
    bool confirmReplacement = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'devices/handshake',
      data: {
        'pairing_code': code,
        ...fingerprint.toJson(),
        'device_fingerprint': fingerprint.toJson(),
        if (confirmReplacement) 'confirm_replacement': true,
      },
    );

    return response.data ?? <String, dynamic>{};
  }
}

/// Provider del DataSource.
final handshakeRemoteDataSourceProvider = Provider<HandshakeRemoteDataSource>((
  ref,
) {
  final dio = ref.watch(dioProvider);
  return HandshakeRemoteDataSource(dio);
});
