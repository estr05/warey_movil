// lib/features/handshake/data/datasources/handshake_remote_datasource.dart
//
// Feature: Handshake — Capa Data (Remote DataSource)
// Responsabilidad ÚNICA: ejecutar la petición HTTP al endpoint de vinculación.
// No contiene lógica de negocio; sólo traduce la respuesta a un Map tipado.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';

/// Modelo interno de la respuesta del handshake.
/// Representa el campo `data` del contrato de la API DevUbi.
class HandshakeResponseData {
  final String token;

  const HandshakeResponseData({required this.token});

  factory HandshakeResponseData.fromJson(Map<String, dynamic> json) {
    return HandshakeResponseData(
      token: json['token'] as String,
    );
  }
}

/// DataSource remoto para el módulo de Handshake.
class HandshakeRemoteDataSource {
  final Dio _dio;

  const HandshakeRemoteDataSource(this._dio);

  /// Envía el código de emparejamiento y el UUID de hardware al servidor.
  ///
  /// Contrato del endpoint:
  /// POST /api/v1/devices/handshake
  /// Body: { "pairing_code": "XXXX-XXXX", "device_uuid": "[uuid]" }
  ///
  /// Respuesta exitosa (200):
  /// { "success": true, "message": "...", "data": { "token": "..." } }
  ///
  /// Lanza [DioException] en caso de error HTTP o de red.
  Future<HandshakeResponseData> validatePairingCode({
    required String code,
    required String uuid,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'devices/handshake',
      data: {
        'pairing_code': code,
        'device_uuid': uuid,
      },
    );

    // El contrato de la API siempre retorna data en response.data['data']
    final responseBody = response.data;
    if (responseBody == null || responseBody['data'] == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Respuesta del servidor inesperada: campo data ausente.',
        type: DioExceptionType.badResponse,
      );
    }

    return HandshakeResponseData.fromJson(
      responseBody['data'] as Map<String, dynamic>,
    );
  }
}

/// Provider del DataSource.
final handshakeRemoteDataSourceProvider =
    Provider<HandshakeRemoteDataSource>((ref) {
  final dio = ref.watch(dioProvider);
  return HandshakeRemoteDataSource(dio);
});
