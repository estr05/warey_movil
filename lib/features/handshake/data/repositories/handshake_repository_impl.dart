// lib/features/handshake/data/repositories/handshake_repository_impl.dart
//
// Feature: Handshake - Capa Data (Implementacion del Repositorio)
// Traduce respuestas del backend a resultados de UX. No decide ownership,
// reemplazos ni validez de seguridad localmente.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/handshake_repository.dart';
import '../datasources/handshake_remote_datasource.dart';
import '../../../../core/services/device_uuid_service.dart';
import '../../../../core/services/secure_storage_service.dart';

class HandshakeRepositoryImpl implements HandshakeRepository {
  final HandshakeRemoteDataSource _dataSource;
  final SecureStorageService _secureStorage;

  const HandshakeRepositoryImpl({
    required HandshakeRemoteDataSource dataSource,
    required SecureStorageService secureStorage,
  }) : _dataSource = dataSource,
       _secureStorage = secureStorage;

  @override
  Future<HandshakeResult> validatePairingCode({
    required String code,
    required DeviceFingerprint fingerprint,
    bool confirmReplacement = false,
  }) async {
    try {
      final responseBody = await _dataSource.validatePairingCode(
        code: code,
        fingerprint: fingerprint,
        confirmReplacement: confirmReplacement,
      );

      return await _parseBackendDecision(
        responseBody,
        fingerprint: fingerprint,
      );
    } on DioException catch (e) {
      final body = _asStringKeyedMap(e.response?.data);
      final retryAfter = _retryAfter(e);

      if (body.isNotEmpty) {
        return await _parseBackendDecision(
          body,
          statusCode: e.response?.statusCode,
          fingerprint: fingerprint,
          retryAfter: retryAfter,
        );
      }

      return HandshakeFailure(
        _networkMessage(e),
        visualStatus: _isNetworkOffline(e)
            ? PairingLifecycleStatus.offline
            : PairingLifecycleStatus.pending,
        cooldown: retryAfter ?? const Duration(seconds: 5),
      );
    } catch (e) {
      return HandshakeFailure('Error inesperado: ${e.runtimeType}');
    }
  }

  Future<HandshakeResult> _parseBackendDecision(
    Map<String, dynamic> body, {
    required DeviceFingerprint fingerprint,
    int? statusCode,
    Duration? retryAfter,
  }) async {
    final message =
        _readString(body, const [
          ['message'],
          ['error'],
          ['data', 'message'],
        ]) ??
        'No se pudo completar la vinculacion.';

    if (statusCode == 401 ||
        statusCode == 403 ||
        _readBool(body, const [
          ['revoked'],
          ['session_revoked'],
          ['data', 'revoked'],
          ['data', 'session_revoked'],
        ])) {
      await _secureStorage.deleteToken();
      return HandshakeSessionRevoked(message);
    }

    if (_readBool(body, const [
      ['requires_confirmation'],
      ['requiresConfirmation'],
      ['data', 'requires_confirmation'],
      ['data', 'requiresConfirmation'],
    ])) {
      return HandshakeRequiresConfirmation(_parseConflict(body));
    }

    if (_isExpiredResponse(body, statusCode, message)) {
      return HandshakeCodeExpired(
        message,
        cooldown: retryAfter ?? const Duration(seconds: 3),
      );
    }

    final token = _readString(body, const [
      ['data', 'token'],
      ['token'],
      ['access_token'],
    ]);
    final success = _readBool(body, const [
      ['success'],
      ['ok'],
      ['data', 'success'],
    ]);

    if (success || token != null) {
      if (token == null || token.isEmpty) {
        return const HandshakeFailure(
          'El backend confirmo la vinculacion, pero no devolvio token.',
        );
      }

      await _secureStorage.saveToken(token);
      return HandshakeSuccess(_parsePairedDevice(body, fingerprint));
    }

    return HandshakeFailure(
      message,
      cooldown: retryAfter ?? const Duration(seconds: 3),
    );
  }

  PairingConflict _parseConflict(Map<String, dynamic> body) {
    final data =
        _readMap(body, const [
          ['data'],
        ]) ??
        body;
    final device =
        _readMap(data, const [
          ['device'],
          ['linked_device'],
          ['paired_device'],
          ['current_device'],
        ]) ??
        data;

    return PairingConflict(
      alias:
          _readString(device, const [
            ['alias'],
            ['name'],
            ['model'],
          ]) ??
          'Telefono vinculado',
      message:
          _readString(body, const [
            ['message'],
            ['data', 'message'],
          ]) ??
          'Este dispositivo ya esta vinculado a otro telefono.',
      fingerprint:
          _readString(device, const [
            ['fingerprint'],
            ['fingerprint_hash'],
            ['device_fingerprint'],
            ['device_fingerprint', 'hash'],
          ]) ??
          'No disponible',
      lastSeenAt: _readDate(device, const [
        ['last_seen_at'],
        ['last_seen'],
        ['last_connection'],
        ['last_connected_at'],
        ['updated_at'],
      ]),
    );
  }

  PairedDeviceInfo _parsePairedDevice(
    Map<String, dynamic> body,
    DeviceFingerprint fallbackFingerprint,
  ) {
    final data =
        _readMap(body, const [
          ['data'],
        ]) ??
        body;
    final device =
        _readMap(data, const [
          ['device'],
          ['paired_device'],
          ['linked_device'],
        ]) ??
        data;
    final responseFingerprint =
        _readMap(device, const [
          ['device_fingerprint'],
          ['fingerprint'],
        ]) ??
        _readMap(data, const [
          ['device_fingerprint'],
          ['fingerprint'],
        ]);

    final statusLabel =
        _readString(device, const [
          ['status'],
          ['pairing_status'],
        ]) ??
        'active';

    return PairedDeviceInfo(
      alias:
          _readString(device, const [
            ['alias'],
            ['name'],
          ]) ??
          fallbackFingerprint.model,
      status: _statusFromBackend(statusLabel),
      pairedAt:
          _readDate(device, const [
            ['paired_at'],
            ['linked_at'],
            ['activated_at'],
            ['created_at'],
            ['updated_at'],
          ]) ??
          DateTime.now(),
      lastSeenAt: _readDate(device, const [
        ['last_seen_at'],
        ['last_seen'],
        ['last_connection'],
        ['updated_at'],
      ]),
      fingerprint:
          _readString(device, const [
            ['fingerprint'],
            ['fingerprint_hash'],
          ]) ??
          _readString(responseFingerprint, const [
            ['hash'],
            ['fingerprint'],
          ]) ??
          _shortFingerprint(fallbackFingerprint.deviceUuid),
      model:
          _readString(responseFingerprint, const [
            ['model'],
          ]) ??
          _readString(device, const [
            ['model'],
          ]) ??
          fallbackFingerprint.model,
      manufacturer:
          _readString(responseFingerprint, const [
            ['manufacturer'],
          ]) ??
          _readString(device, const [
            ['manufacturer'],
          ]) ??
          fallbackFingerprint.manufacturer,
      androidVersion:
          _readString(responseFingerprint, const [
            ['android_version'],
          ]) ??
          _readString(device, const [
            ['android_version'],
          ]) ??
          fallbackFingerprint.androidVersion,
      appVersion:
          _readString(responseFingerprint, const [
            ['app_version'],
          ]) ??
          _readString(device, const [
            ['app_version'],
          ]) ??
          fallbackFingerprint.appVersion,
    );
  }

  PairingLifecycleStatus _statusFromBackend(String status) {
    return switch (status.toLowerCase().replaceAll('-', '_')) {
      'active' => PairingLifecycleStatus.active,
      'paired' || 'linked' => PairingLifecycleStatus.paired,
      'revoked' || 'disabled' => PairingLifecycleStatus.revoked,
      'offline' || 'inactive' => PairingLifecycleStatus.offline,
      _ => PairingLifecycleStatus.pending,
    };
  }

  bool _isExpiredResponse(
    Map<String, dynamic> body,
    int? statusCode,
    String message,
  ) {
    final explicitExpired = _readBool(body, const [
      ['expired'],
      ['code_expired'],
      ['pairing_code_expired'],
      ['data', 'expired'],
      ['data', 'code_expired'],
      ['data', 'pairing_code_expired'],
    ]);
    final messageLooksExpired =
        message.toLowerCase().contains('expir') ||
        message.toLowerCase().contains('vencid') ||
        message.toLowerCase().contains('expired');

    return explicitExpired ||
        statusCode == 410 ||
        ((statusCode == 404 || statusCode == 422) && messageLooksExpired);
  }

  String _networkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'El servidor tardo demasiado en responder. Intenta de nuevo en unos segundos.';
      case DioExceptionType.connectionError:
        return 'No se pudo conectar al servidor. Revisa tu conexion y vuelve a intentar.';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        return 'Error del servidor ($statusCode). Intenta de nuevo.';
      default:
        return e.message ?? 'Ocurrio un error de red desconocido.';
    }
  }

  bool _isNetworkOffline(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
  }

  Duration? _retryAfter(DioException e) {
    final rawValue = e.response?.headers.value('retry-after');
    final seconds = int.tryParse(rawValue ?? '');
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  String _shortFingerprint(String deviceUuid) {
    final cleaned = deviceUuid.replaceAll('-', '');
    if (cleaned.length <= 12) return cleaned;
    return '${cleaned.substring(0, 6)}...${cleaned.substring(cleaned.length - 6)}';
  }

  Map<String, dynamic> _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _readMap(
    Map<String, dynamic>? body,
    List<List<String>> paths,
  ) {
    if (body == null) return null;

    for (final path in paths) {
      final value = _valueAt(body, path);
      final mapped = _asStringKeyedMap(value);
      if (mapped.isNotEmpty) return mapped;
    }

    return null;
  }

  String? _readString(Map<String, dynamic>? body, List<List<String>> paths) {
    if (body == null) return null;

    for (final path in paths) {
      final value = _valueAt(body, path);
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }

    return null;
  }

  bool _readBool(Map<String, dynamic> body, List<List<String>> paths) {
    for (final path in paths) {
      final value = _valueAt(body, path);
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.toLowerCase().trim();
        if (normalized == 'true' || normalized == '1') return true;
      }
      if (value is num && value == 1) return true;
    }

    return false;
  }

  DateTime? _readDate(Map<String, dynamic>? body, List<List<String>> paths) {
    final value = _readString(body, paths);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  dynamic _valueAt(Map<String, dynamic> body, List<String> path) {
    dynamic current = body;

    for (final key in path) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else if (current is Map) {
        current = current[key];
      } else {
        return null;
      }
    }

    return current;
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
