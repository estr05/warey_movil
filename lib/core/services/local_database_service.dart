// lib/core/services/local_database_service.dart
//
// Capa Core — Motor de Persistencia Local (SQLite)
// Responsabilidad: gestionar el ciclo de vida de la base de datos SQLite local
// que actúa como cola offline para los frames de telemetría no enviados.
//
// Patrón Singleton: la instancia de Database se inicializa una sola vez y se
// reutiliza durante todo el ciclo de vida de la aplicación para evitar abrir
// múltiples conexiones concurrentes al mismo archivo de BD.

import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDatabaseService {
  // ── Constantes de esquema ───────────────────────────────────────────────────
  static const String _dbName = 'devubi_telemetry.db';
  static const int _dbVersion = 1;
  static const String _tableName = 'offline_telemetry';

  // Columnas
  static const String colId = 'id';
  static const String colLatitude = 'latitude';
  static const String colLongitude = 'longitude';
  static const String colBatteryLevel = 'battery_level';
  static const String colIsCharging = 'is_charging';
  static const String colConnectionType = 'connection_type';
  static const String colCreatedAt = 'created_at';

  // ── Singleton ───────────────────────────────────────────────────────────────
  Database? _db;

  /// Retorna la instancia activa de la BD, inicializándola si aún no existe.
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final fullPath = p.join(databasesPath, _dbName);

    dev.log(
      '[LocalDB] Abriendo base de datos en: $fullPath',
      name: 'LocalDatabaseService',
    );

    return openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Crea el esquema de la tabla en la primera apertura.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        $colId              INTEGER PRIMARY KEY AUTOINCREMENT,
        $colLatitude        REAL    NOT NULL,
        $colLongitude       REAL    NOT NULL,
        $colBatteryLevel    INTEGER NOT NULL,
        $colIsCharging      INTEGER NOT NULL,
        $colConnectionType  TEXT    NOT NULL,
        $colCreatedAt       TEXT    NOT NULL
      )
    ''');

    dev.log(
      '[LocalDB] Tabla "$_tableName" creada (v$version).',
      name: 'LocalDatabaseService',
    );
  }

  /// Hook de migración para versiones futuras del esquema.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    dev.log(
      '[LocalDB] Migrando BD: v$oldVersion → v$newVersion.',
      name: 'LocalDatabaseService',
    );
    // Espacio reservado para migraciones futuras sin romper datos existentes.
  }

  // ── API Pública ─────────────────────────────────────────────────────────────

  /// Inserta un frame de telemetría en la cola offline.
  ///
  /// [frame] debe contener las claves: latitude, longitude, battery_level,
  /// is_charging (int 0/1), connection_type, created_at.
  ///
  /// Retorna el `id` generado por AUTOINCREMENT, o -1 si la inserción falló.
  Future<int> insertFrame(Map<String, dynamic> frame) async {
    try {
      final db = await database;
      final id = await db.insert(
        _tableName,
        frame,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      dev.log(
        '[LocalDB] Frame insertado — id: $id | lat: ${frame[colLatitude]} lng: ${frame[colLongitude]}',
        name: 'LocalDatabaseService',
      );
      return id;
    } catch (e, st) {
      dev.log(
        '[LocalDB] ERROR al insertar frame: $e',
        name: 'LocalDatabaseService',
        error: e,
        stackTrace: st,
      );
      return -1;
    }
  }

  /// Recupera todos los frames pendientes en orden cronológico estricto (FIFO).
  ///
  /// Los frames se retornan ordenados por `id` ASC para garantizar que los más
  /// antiguos se sincronizan primero al recuperar la conectividad.
  Future<List<Map<String, dynamic>>> getPendingFrames() async {
    try {
      final db = await database;
      final frames = await db.query(
        _tableName,
        orderBy: '$colId ASC',
      );
      dev.log(
        '[LocalDB] ${frames.length} frame(s) pendiente(s) recuperado(s).',
        name: 'LocalDatabaseService',
      );
      return frames;
    } catch (e, st) {
      dev.log(
        '[LocalDB] ERROR al leer frames pendientes: $e',
        name: 'LocalDatabaseService',
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Elimina los frames cuyos `id` están en [ids] de la cola offline.
  ///
  /// Esta operación debe invocarse SÓLO tras recibir confirmación HTTP 200/201
  /// del backend para garantizar cero pérdida de datos.
  Future<void> deleteFrames(List<int> ids) async {
    if (ids.isEmpty) return;

    try {
      final db = await database;
      final placeholders = List.filled(ids.length, '?').join(', ');
      final deletedCount = await db.delete(
        _tableName,
        where: '$colId IN ($placeholders)',
        whereArgs: ids,
      );
      dev.log(
        '[LocalDB] $deletedCount frame(s) eliminado(s) — ids: $ids',
        name: 'LocalDatabaseService',
      );
    } catch (e, st) {
      dev.log(
        '[LocalDB] ERROR al eliminar frames $ids: $e',
        name: 'LocalDatabaseService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Cierra la conexión a la BD. Debe invocarse al destruir el Provider
  /// si se requiere gestión explícita del ciclo de vida.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      dev.log('[LocalDB] Conexión cerrada.', name: 'LocalDatabaseService');
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

/// Provider global del servicio de base de datos local.
/// El Singleton interno de [LocalDatabaseService] garantiza una sola
/// conexión activa independientemente de cuántas veces se lea este Provider.
final localDatabaseProvider = Provider<LocalDatabaseService>((ref) {
  final service = LocalDatabaseService();

  // Cierra la BD limpiamente cuando el Provider sea destruido.
  ref.onDispose(service.close);

  return service;
});
