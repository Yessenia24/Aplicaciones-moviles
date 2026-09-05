import 'package:flutter/material.dart';
import 'ticket_service.dart';
import 'services/secure_storage_service.dart';
import 'services/local_db_service.dart';

class TicketsScreen extends StatefulWidget {
  final int idUsuario;
  const TicketsScreen({Key? key, required this.idUsuario}) : super(key: key);

  @override
  _TicketsScreenState createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  late Future<List<dynamic>> _ticketsFuture;

  // Variables para controlar el estado offline y la fecha de caché
  bool _isOffline = false;
  String _cachedAt = DateTime.now().toIso8601String();

  // Controladores para el formulario de nuevo ticket
  final TextEditingController _descCtrl = TextEditingController();
  String _prioridad = 'Media';

  @override
  void initState() {
    super.initState();
    _refrescarTickets();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  void _refrescarTickets() {
    setState(() {
      _ticketsFuture = TicketService.getTickets(widget.idUsuario).then((tickets) {
        // Conexión exitosa al backend
        _cachedAt = DateTime.now().toIso8601String();
        _isOffline = false;
        return tickets;
      }).catchError((error) async {
        // Falló la red: activamos modo offline y leemos desde SQLite local
        setState(() {
          _isOffline = true;
        });

        try {
          final localTickets = await LocalDbService.getLocalTickets(widget.idUsuario);
          return localTickets;
        } catch (_) {
          return <dynamic>[];
        }
      });
    });
  }

  // Creación de ticket con soporte offline
  Future<void> _crearTicket() async {
    final desc = _descCtrl.text.trim();
    if (desc.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La descripción debe tener al menos 10 caracteres')),
      );
      return;
    }

    try {
      bool creado = await TicketService.createTicket(
        idUsuario: widget.idUsuario,
        descripcion: desc,
        prioridad: _prioridad,
      );

      if (creado) {
        _descCtrl.clear();
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isOffline
                ? 'Guardado localmente en cola de espera'
                : 'Ticket creado con éxito'),
          ),
        );
        _refrescarTickets();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al procesar ticket: $e')),
      );
    }
  }

  // Modal para registrar un nuevo ticket
  void _mostrarModalCrearTicket() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nuevo Ticket de Soporte',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción de la falla',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _prioridad,
                items: ['Baja', 'Media', 'Alta']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (val) => setModalState(() => _prioridad = val!),
                decoration: const InputDecoration(
                  labelText: 'Prioridad',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(45),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _crearTicket,
                child: const Text('Registrar Ticket'),
              )
            ],
          ),
        ),
      ),
    );
  }

  // Cierre de sesión y purgado integral de datos
  Future<void> handleLogout(BuildContext context) async {
    // 1. Limpieza de tokens en almacenamiento seguro cifrado
    await SecureStorageService.clearAll();

    // 2. Purgado integral de SQLite
    await LocalDbService.purgeDatabase();

    // 3. Redirección al Login
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  // Indicador visual de frescura de datos (Semana 12)
  Widget buildFreshnessIndicator(String cachedAt, bool isOffline) {
    final cacheDate = DateTime.tryParse(cachedAt) ?? DateTime.now();
    final difference = DateTime.now().difference(cacheDate).inMinutes;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOffline ? Colors.orange.shade100 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOffline ? Icons.cloud_off : Icons.cloud_done,
            size: 16,
            color: isOffline ? Colors.orange.shade900 : Colors.green.shade900,
          ),
          const SizedBox(width: 6),
          Text(
            isOffline
                ? 'Sin conexión (hace $difference min)'
                : 'Actualizado hace $difference min',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOffline ? Colors.orange.shade900 : Colors.green.shade900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Tickets de Soporte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar',
            onPressed: _refrescarTickets,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => handleLogout(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarModalCrearTicket,
        tooltip: 'Crear Ticket',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Badge visual de antigüedad / estado en la cabecera
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Center(
              child: buildFreshnessIndicator(_cachedAt, _isOffline),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _ticketsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final tickets = snapshot.data ?? [];
                if (tickets.isEmpty) {
                  return const Center(
                    child: Text('No hay tickets registrados localmente ni en el servidor.'),
                  );
                }

                return ListView.builder(
                  itemCount: tickets.length,
                  itemBuilder: (context, index) {
                    final ticket = tickets[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text('${ticket['id_ticket'] ?? index + 1}'),
                        ),
                        title: Text(ticket['descripcion_falla'] ?? ''),
                        subtitle: Text(
                          'Estado: ${ticket['estado'] ?? 'Pendiente'} | Prioridad: ${ticket['prioridad'] ?? 'Media'}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            bool eliminado =
                                await TicketService.deleteTicket(ticket['id_ticket']);
                            if (eliminado) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ticket eliminado')),
                                );
                              }
                              _refrescarTickets();
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}