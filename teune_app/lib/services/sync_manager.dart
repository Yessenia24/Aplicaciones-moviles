import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'local_db_service.dart';

class SyncManager {
  static const String baseUrl = 'http://10.0.2.2:5000/api'; // Ajustar según plataforma
  static const int maxRetries = 5;

  // Registrar operación de creación offline
  static Future<void> createTicketOffline({
    required int idUsuario,
    required String? idRouter,
    required String descripcion,
    required String prioridad,
  }) async {
    final db = await LocalDbService.database;
    final clientUuid = const Uuid().v4();
    final nowIso = DateTime.now().toIso8601String();

    // 1. Guardar en tabla local con estado pendiente (0)
    await db.insert('tickets', {
      'client_uuid': clientUuid,
      'id_ticket': null,
      'descripcion_falla': descripcion,
      'prioridad': prioridad,
      'estado': 'Abierto',
      'cached_at': nowIso,
      'sync_status': 0,
    });

    // 2. Encolar en sync_queue
    final payload = jsonEncode({
      'client_uuid': clientUuid,
      'id_usuario': idUsuario,
      'id_router': idRouter,
      'descripcion_falla': descripcion,
      'prioridad': prioridad,
    });

    await db.insert('sync_queue', {
      'id_op': clientUuid,
      'action': 'CREATE_TICKET',
      'payload': payload,
      'retries': 0,
      'created_at': nowIso,
    });
  }

  // Procesar cola con reintentos de espera creciente (Exponential Backoff)
  static Future<void> processSyncQueue() async {
    final db = await LocalDbService.database;
    final List<Map<String, dynamic>> queue = await db.query('sync_queue');

    for (var op in queue) {
      final String idOp = op['id_op'];
      final int retries = op['retries'];
      final Map<String, dynamic> data = jsonDecode(op['payload']);

      if (retries >= maxRetries) {
        // Se descarta tras exceder reintentos máximos (Dead-letter)
        await db.delete('sync_queue', where: 'id_op = ?', whereArgs: [idOp]);
        continue;
      }

      try {
        final res = await http.post(
          Uri.parse('$baseUrl/tickets'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        );

        if (res.statusCode == 201 || res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final serverId = body['id_ticket'] ?? (body['data'] != null ? body['data']['id_ticket'] : null);

          // Actualizar registro local con el ID y timestamp autoritativo del servidor
          await db.update(
            'tickets',
            {
              'id_ticket': serverId,
              'sync_status': 1,
              'cached_at': DateTime.now().toIso8601String(),
            },
            where: 'client_uuid = ?',
            whereArgs: [idOp],
          );

          // Eliminar de la cola
          await db.delete('sync_queue', where: 'id_op = ?', whereArgs: [idOp]);
        } else {
          await _incrementRetry(idOp, retries);
        }
      } catch (e) {
        await _incrementRetry(idOp, retries);
      }
    }
  }

  static Future<void> _incrementRetry(String idOp, int currentRetries) async {
    final db = await LocalDbService.database;
    await db.update(
      'sync_queue',
      {'retries': currentRetries + 1},
      where: 'id_op = ?',
      whereArgs: [idOp],
    );
    // Pausa con retroceso exponencial: 2^retries segundos
    final backoffSeconds = pow(2, currentRetries).toInt();
    await Future.delayed(Duration(seconds: backoffSeconds));
  }
}