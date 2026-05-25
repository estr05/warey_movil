// lib/core/services/local_database_service.dart
//
// Capa Core — Motor de Persistencia Local (SQLite)
//
// v2: Esquema con 3 tablas separadas:
//   - offline_telemetry:     Cola legacy (retrocompatibilidad).
//   - offline_location:      Cola de frames de ubicación GPS.
//   - offline_device_status: Cola de frames de estado del dispositivo.
//
// Patrón Singleton: la instancia de Database se inicializa una sola vez y se
// reutiliza durante todo el ciclo de vida de la aplicación.

import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDatabaseService {
  // ── Constantes de esquema ───────────────────────────────────────────────────
  static const String _dbName = 'devubi_telemetry.db';
  static const int _dbVersion = 5; // v5: bearing en offline_location

  // ── Nombres de tabla ────────────────────────────────────────────────────────
  static const String _tableTelemetry = 'offline_telemetry';
  static const String _tableLocation = 'offline_location';
  static const String _tableDeviceStatus = 'offline_device_status';

  // Columnas compartidas
  static const String colId = 'id';
  static const String colCreatedAt = 'created_at';

  // Columnas legacy / telemetría unificada
  static const String colLatitude = 'latitude';
  static const String colLongitude = 'longitude';
  static const String colBatteryLevel = 'battery_level';
  static const String colIsCharging = 'is_charging';
  static const String colConnectionType = 'connection_type';

  // Columnas de ubicación GPS (nueva arquitectura)
  static const String colAccuracy = 'accuracy';
  static const String colSpeed = 'speed';
  static const String colSmoothedSpeed = 'smoothed_speed';
  static const String colMovementType = 'movement_type';
  static const String colAltitude = 'altitude';
  static const String colTrackingState = 'tracking_state';
  static const String colIsSafeZone = 'is_safe_zone';
  static const String colZoneName = 'zone_name';
  static const String colBearing = 'bearing';
  static const String colCapturedAt = 'captured_at';

  // Columnas de estado del dispositivo (nueva arquitectura)
  static const String colSignalStrength = 'signal_strength';
  static const String colHasInternet = 'has_internet';
  static const String colActivityStatus = 'activity_status';
  static const String colScreenActive = 'screen_active';

  // ── Singleton ───────────────────────────────────────────────────────────────
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final fullPath = p.join(databasesPath, _dbName);
    dev.log('[LocalDB] Abriendo BD: $fullPath', name: 'LocalDatabaseService');
    return openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTableTelemetryLegacy(db);
    await _createTableLocation(db);
    await _createTableDeviceStatus(db);
    dev.log('[LocalDB] Esquema v$version creado (3 tablas).', name: 'LocalDatabaseService');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    dev.log('[LocalDB] Migrando BD: v$oldVersion → v$newVersion.', name: 'LocalDatabaseService');
    if (oldVersion < 2) {
      // v1 → v2: crear tablas separadas de ubicación y estado
      await _createTableLocation(db);
      await _createTableDeviceStatus(db);
      dev.log('[LocalDB] Migración v1→v2: tablas de ubicación y estado creadas.', name: 'LocalDatabaseService');
    }
    if (oldVersion < 3) {
      // v2 → v3: agregar movement_type y smoothed_speed a offline_location
      // ALTER TABLE es seguro: agrega columnas nullable sin tocar datos existentes.
      try {
        await db.execute('ALTER TABLE $_tableLocation ADD COLUMN $colMovementType TEXT');
        await db.execute('ALTER TABLE $_tableLocation ADD COLUMN $colSmoothedSpeed REAL');
        dev.log('[LocalDB] Migración v2→v3: columnas movement_type y smoothed_speed agregadas.', name: 'LocalDatabaseService');
      } catch (e) {
        // Columnas ya existen (p.ej. instalación directa desde v3). Ignorar.
        dev.log('[LocalDB] Migración v2→v3: columnas ya existentes — omitida.', name: 'LocalDatabaseService');
      }
    }
    if (oldVersion < 4) {
      // v3 → v4: agregar screen_active a offline_device_status.
      // DEFAULT -1 representa null (estado desconocido) para filas existentes.
      try {
        await db.execute(
          'ALTER TABLE $_tableDeviceStatus ADD COLUMN $colScreenActive INTEGER NOT NULL DEFAULT -1',
        );
        dev.log('[LocalDB] Migración v3→v4: columna screen_active agregada.', name: 'LocalDatabaseService');
      } catch (e) {
        dev.log('[LocalDB] Migración v3→v4: columna ya existente — omitida.', name: 'LocalDatabaseService');
      }
    }
    if (oldVersion < 5) {
      // v4 → v5: agregar bearing a offline_location
      try {
        await db.execute('ALTER TABLE $_tableLocation ADD COLUMN $colBearing REAL');
        dev.log('[LocalDB] Migración v4→v5: columna bearing agregada.', name: 'LocalDatabaseService');
      } catch (e) {
        dev.log('[LocalDB] Migración v4→v5: columna ya existente — omitida.', name: 'LocalDatabaseService');
      }
    }
  }

  Future<void> _createTableTelemetryLegacy(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableTelemetry (
        $colId              INTEGER PRIMARY KEY AUTOINCREMENT,
        $colLatitude        REAL    NOT NULL,
        $colLongitude       REAL    NOT NULL,
        $colBatteryLevel    INTEGER NOT NULL,
        $colIsCharging      INTEGER NOT NULL,
        $colConnectionType  TEXT    NOT NULL,
        $colCreatedAt       TEXT    NOT NULL
      )
    ''');
  }

  Future<void> _createTableLocation(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableLocation (
        $colId              INTEGER PRIMARY KEY AUTOINCREMENT,
        $colLatitude        REAL    NOT NULL,
        $colLongitude       REAL    NOT NULL,
        $colAccuracy        REAL,
        $colSpeed           REAL,
        $colSmoothedSpeed   REAL,
        $colAltitude        REAL,
        $colBearing         REAL,
        $colMovementType    TEXT,
        $colTrackingState   TEXT    NOT NULL,
        $colIsSafeZone      INTEGER NOT NULL DEFAULT 0,
        $colZoneName        TEXT,
        $colCapturedAt      TEXT    NOT NULL
      )
    ''');
  }

  Future<void> _createTableDeviceStatus(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableDeviceStatus (
        $colId              INTEGER PRIMARY KEY AUTOINCREMENT,
        $colBatteryLevel    INTEGER NOT NULL,
        $colIsCharging      INTEGER NOT NULL,
        $colConnectionType  TEXT    NOT NULL,
        $colSignalStrength  INTEGER,
        $colHasInternet     INTEGER NOT NULL DEFAULT 0,
        $colTrackingState   TEXT    NOT NULL,
        $colActivityStatus  TEXT    NOT NULL,
        $colScreenActive    INTEGER NOT NULL DEFAULT -1,
        $colCapturedAt      TEXT    NOT NULL
      )
    ''');
  }

  // ── API Pública — Tabla Legacy ──────────────────────────────────────────────

  Future<int> insertFrame(Map<String, dynamic> frame) async {
    try {
      final db = await database;
      return await db.insert(_tableTelemetry, frame, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      dev.log('[LocalDB] ERROR insertFrame: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingFrames() async {
    try {
      final db = await database;
      return await db.query(_tableTelemetry, orderBy: '$colId ASC');
    } catch (e, st) {
      dev.log('[LocalDB] ERROR getPendingFrames: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
      return [];
    }
  }

  Future<void> deleteFrames(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final db = await database;
      final ph = List.filled(ids.length, '?').join(', ');
      await db.delete(_tableTelemetry, where: '$colId IN ($ph)', whereArgs: ids);
    } catch (e, st) {
      dev.log('[LocalDB] ERROR deleteFrames: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
    }
  }

  // ── API Pública — Tabla de Ubicación GPS ───────────────────────────────────

  Future<int> insertLocationFrame(Map<String, dynamic> frame) async {
    try {
      final db = await database;
      return await db.insert(_tableLocation, frame, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      dev.log('[LocalDB] ERROR insertLocationFrame: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingLocationFrames() async {
    try {
      final db = await database;
      return await db.query(_tableLocation, orderBy: '$colId ASC');
    } catch (e, st) {
      dev.log('[LocalDB] ERROR getPendingLocationFrames: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
      return [];
    }
  }

  Future<void> deleteLocationFrames(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final db = await database;
      final ph = List.filled(ids.length, '?').join(', ');
      await db.delete(_tableLocation, where: '$colId IN ($ph)', whereArgs: ids);
    } catch (e, st) {
      dev.log('[LocalDB] ERROR deleteLocationFrames: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
    }
  }

  // ── API Pública — Tabla de Estado del Dispositivo ──────────────────────────

  Future<int> insertDeviceStatusFrame(Map<String, dynamic> frame) async {
    try {
      final db = await database;
      return await db.insert(_tableDeviceStatus, frame, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      dev.log('[LocalDB] ERROR insertDeviceStatusFrame: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingDeviceStatusFrames() async {
    try {
      final db = await database;
      return await db.query(_tableDeviceStatus, orderBy: '$colId ASC');
    } catch (e, st) {
      dev.log('[LocalDB] ERROR getPendingDeviceStatusFrames: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
      return [];
    }
  }

  Future<void> deleteDeviceStatusFrames(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final db = await database;
      final ph = List.filled(ids.length, '?').join(', ');
      await db.delete(_tableDeviceStatus, where: '$colId IN ($ph)', whereArgs: ids);
    } catch (e, st) {
      dev.log('[LocalDB] ERROR deleteDeviceStatusFrames: $e', name: 'LocalDatabaseService', error: e, stackTrace: st);
    }
  }

  /// Retorna el total de frames pendientes en todas las colas.
  Future<int> getPendingFramesCount() async {
    try {
      final db = await database;
      final r1 = await db.rawQuery('SELECT COUNT(*) FROM $_tableTelemetry');
      final r2 = await db.rawQuery('SELECT COUNT(*) FROM $_tableLocation');
      final r3 = await db.rawQuery('SELECT COUNT(*) FROM $_tableDeviceStatus');
      return (Sqflite.firstIntValue(r1) ?? 0) +
          (Sqflite.firstIntValue(r2) ?? 0) +
          (Sqflite.firstIntValue(r3) ?? 0);
    } catch (e) {
      return 0;
    }
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      dev.log('[LocalDB] Conexión cerrada.', name: 'LocalDatabaseService');
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final localDatabaseProvider = Provider<LocalDatabaseService>((ref) {
  final service = LocalDatabaseService();
  ref.onDispose(service.close);
  return service;
});
