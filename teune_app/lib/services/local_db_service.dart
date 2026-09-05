import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDbService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'teune_local.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // 1. Entidad principal offline
        await db.execute('''
          CREATE TABLE tickets (
            client_uuid TEXT PRIMARY KEY,
            id_ticket INTEGER NULL,
            id_usuario INTEGER NULL,
            descripcion_falla TEXT NOT NULL,
            prioridad TEXT NOT NULL,
            estado TEXT NOT NULL,
            cached_at TEXT NOT NULL,
            sync_status INTEGER NOT NULL DEFAULT 1
          )
        ''');

        // 2. Cola de operaciones pendientes
        await db.execute('''
          CREATE TABLE sync_queue (
            id_op TEXT PRIMARY KEY,
            action TEXT NOT NULL,
            payload TEXT NOT NULL,
            retries INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // Obtener tickets almacenados localmente para lectura offline
  static Future<List<Map<String, dynamic>>> getLocalTickets([int? idUsuario]) async {
    final db = await database;
    if (idUsuario != null) {
      return await db.query(
        'tickets',
        where: 'id_usuario = ? OR id_usuario IS NULL',
        whereArgs: [idUsuario],
        orderBy: 'cached_at DESC',
      );
    }
    return await db.query('tickets', orderBy: 'cached_at DESC');
  }

  // Guardar o actualizar la lista de tickets traídos de la API en local
  static Future<void> saveTickets(List<dynamic> remoteTickets, int idUsuario) async {
    final db = await database;
    final batch = db.batch();

    for (var ticket in remoteTickets) {
      batch.insert(
        'tickets',
        {
          'client_uuid': ticket['client_uuid'] ?? 'ticket_${ticket['id_ticket']}',
          'id_ticket': ticket['id_ticket'],
          'id_usuario': idUsuario,
          'descripcion_falla': ticket['descripcion_falla'] ?? '',
          'prioridad': ticket['prioridad'] ?? 'Media',
          'estado': ticket['estado'] ?? 'Pendiente',
          'cached_at': DateTime.now().toIso8601String(),
          'sync_status': 1, // Sincronizado
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Insertar un ticket creado localmente en modo offline
  static Future<void> insertTicketLocal({
    required String uuid,
    required int idUsuario,
    required String descripcion,
    required String prioridad,
  }) async {
    final db = await database;
    await db.insert(
      'tickets',
      {
        'client_uuid': uuid,
        'id_ticket': null,
        'id_usuario': idUsuario,
        'descripcion_falla': descripcion,
        'prioridad': prioridad,
        'estado': 'Pendiente (Offline)',
        'cached_at': DateTime.now().toIso8601String(),
        'sync_status': 0, // Pendiente de sincronizar
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Registrar operación en cola de sincronización
  static Future<void> addToSyncQueue({
    required String idOp,
    required String action,
    required String payload,
  }) async {
    final db = await database;
    await db.insert(
      'sync_queue',
      {
        'id_op': idOp,
        'action': action,
        'payload': payload,
        'retries': 0,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Obtener operaciones pendientes por sincronizar
  static Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final db = await database;
    return await db.query('sync_queue', orderBy: 'created_at ASC');
  }

  // Purgado integral de SQLite al cerrar sesión
  static Future<void> purgeDatabase() async {
    final db = await database;
    await db.delete('tickets');
    await db.delete('sync_queue');
  }
}