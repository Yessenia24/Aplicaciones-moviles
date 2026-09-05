import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'services/local_db_service.dart';

class TicketService {
  // IP correcta para celular físico conectado al mismo Wi-Fi y para Web
  static const String baseUrl = 'http://192.168.0.6:5000/api';

  // 1. Obtener listado de tickets (Online con respaldo automático en SQLite)
  static Future<List<dynamic>> getTickets(int idUsuario) async {
    final url = Uri.parse('$baseUrl/tickets/usuario/$idUsuario');

    try {
      final response = await http
          .get(url)
          .timeout(const Duration(seconds: 4)); // Detecta rápidamente si no hay internet

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        final List<dynamic> tickets = decodedData['data'] ?? [];

        // Guarda en base de datos local SQLite para cuando se active el modo avión
        await LocalDbService.saveTickets(tickets, idUsuario);

        return tickets;
      } else {
        debugPrint('Error del servidor: ${response.statusCode} - ${response.body}');
        return await LocalDbService.getLocalTickets(idUsuario);
      }
    } catch (e) {
      debugPrint('Modo sin conexión detectado, leyendo SQLite local: $e');
      // Si falla la red (ej. modo avión), recupera los tickets guardados localmente
      return await LocalDbService.getLocalTickets(idUsuario);
    }
  }

  // 2. Registrar un nuevo ticket (Online o encolado local Offline)
  static Future<bool> createTicket({
    required int idUsuario,
    String? idRouter = 'RT-001',
    required String descripcionFalla,
    String prioridad = 'Media',
  }) async {
    final url = Uri.parse('$baseUrl/tickets');
    final clientUuid = 'client_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'id_usuario': idUsuario,
              'id_router': idRouter,
              'descripcion_falla': descripcionFalla,
              'prioridad': prioridad,
              'client_uuid': clientUuid,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 201) {
        return true;
      } else {
        debugPrint('Error al crear ticket en API: ${response.statusCode}');
        throw Exception('Fallo de respuesta HTTP');
      }
    } catch (e) {
      debugPrint('Guardando ticket localmente en cola offline: $e');
      
      // Inserta el ticket en SQLite con estado pendiente
      await LocalDbService.insertTicketLocal(
        uuid: clientUuid,
        idUsuario: idUsuario,
        descripcion: descripcionFalla,
        prioridad: prioridad,
      );

      // Agrega la operación a la cola para sincronizar al volver la red
      await LocalDbService.addToSyncQueue(
        idOp: clientUuid,
        action: 'CREATE_TICKET',
        payload: jsonEncode({
          'id_usuario': idUsuario,
          'id_router': idRouter,
          'descripcion_falla': descripcionFalla,
          'prioridad': prioridad,
        }),
      );

      return true;
    }
  }

  // 3. Baja lógica de un ticket (DELETE)
  static Future<bool> deleteTicket(dynamic idTicket) async {
    if (idTicket == null) return false;
    final url = Uri.parse('$baseUrl/tickets/$idTicket');

    try {
      final response = await http
          .delete(url)
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error al eliminar ticket: $e');
      return false;
    }
  }
}