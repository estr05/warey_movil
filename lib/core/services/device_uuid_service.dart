// lib/core/services/device_uuid_service.dart
//
// Capa Core - Fingerprint local del dispositivo.
// Flutter no usa estos datos para decidir ownership. Solo arma un payload
// descriptivo para que el backend seguro evalue el handshake.

import 'dart:io' show Platform;
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'secure_storage_service.dart';

class DeviceFingerprint {
  final String deviceUuid;
  final String model;
  final String manufacturer;
  final String androidVersion;
  final String appVersion;

  const DeviceFingerprint({
    required this.deviceUuid,
    required this.model,
    required this.manufacturer,
    required this.androidVersion,
    required this.appVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_uuid': deviceUuid,
      'model': model,
      'manufacturer': manufacturer,
      'android_version': androidVersion,
      'app_version': appVersion,
    };
  }
}

class DeviceUuidService {
  final DeviceInfoPlugin _deviceInfo;
  final SecureStorageService _secureStorage;
  final Random _random;

  DeviceUuidService({
    DeviceInfoPlugin? deviceInfo,
    SecureStorageService? secureStorage,
    Random? random,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _secureStorage = secureStorage ?? SecureStorageService(),
       _random = random ?? Random.secure();

  /// Retorna un UUID estable por instalacion, guardado en secure storage.
  ///
  /// No depende de identificadores de hardware sensibles o inestables. Si la app
  /// se reinstala, el backend debe decidir si acepta o no el nuevo UUID.
  Future<String> getDeviceUuid() async {
    final storedUuid = await _secureStorage.readDeviceUuid();
    if (storedUuid != null && storedUuid.isNotEmpty) {
      return storedUuid;
    }

    final generatedUuid = _generateUuidV4();
    await _secureStorage.saveDeviceUuid(generatedUuid);
    return generatedUuid;
  }

  /// Construye el fingerprint enviado al backend durante el handshake.
  Future<DeviceFingerprint> getDeviceFingerprint() async {
    final deviceUuid = await getDeviceUuid();
    final appVersion = await _readAppVersion();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return DeviceFingerprint(
          deviceUuid: deviceUuid,
          model: _safeValue(androidInfo.model, 'Android device'),
          manufacturer: _safeValue(androidInfo.manufacturer, 'Android'),
          androidVersion:
              'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})',
          appVersion: appVersion,
        );
      }

      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return DeviceFingerprint(
          deviceUuid: deviceUuid,
          model: _safeValue(iosInfo.utsname.machine, 'iPhone'),
          manufacturer: 'Apple',
          androidVersion: 'iOS ${iosInfo.systemVersion}',
          appVersion: appVersion,
        );
      }
    } catch (_) {
      // Si el plugin nativo falla, mantenemos el UUID estable y degradamos
      // solo los metadatos visuales. El backend sigue siendo la autoridad.
    }

    return DeviceFingerprint(
      deviceUuid: deviceUuid,
      model: 'Dispositivo desconocido',
      manufacturer: 'Desconocido',
      androidVersion: 'Sistema desconocido',
      appVersion: appVersion,
    );
  }

  Future<String> _readAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final build = packageInfo.buildNumber.isEmpty
          ? ''
          : '+${packageInfo.buildNumber}';
      return '${packageInfo.version}$build';
    } catch (_) {
      return '1.0.0';
    }
  }

  String _safeValue(String? value, String fallback) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return fallback;
    return trimmed;
  }

  String _generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20, 32),
    ].join('-');
  }
}
