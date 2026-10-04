import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'services/secure_storage_service.dart';
import 'services/local_db_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teune Móvil',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3949AB)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

// 1. EVALUACIÓN DE SESIÓN PERSISTENTE AL ARRANCAR
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final token = await SecureStorageService.getToken();
    final userIdStr = await SecureStorageService.getUserId();

    if (!mounted) return;

    if (token != null && userIdStr != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => TeuneDashboardScreen(userId: int.parse(userIdStr)),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFF3949AB))),
    );
  }
}

// 2. PANTALLA DE INICIO DE SESIÓN
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailCtrl = TextEditingController(text: 'usuario@teune.com');
  final _passCtrl = TextEditingController(text: '123456');
  bool _loading = false;

  Future<void> _login() async {
    setState(() => _loading = true);
    // Guarda credenciales en almacenamiento seguro cifrado nativo (Keystore/Keychain)
    await SecureStorageService.saveAuthData(
      token: 'jwt_secure_token_teune_2026',
      idUsuario: '1',
    );

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const TeuneDashboardScreen(userId: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_tethering, size: 75, color: Color(0xFF3949AB)),
              const SizedBox(height: 12),
              const Text(
                'TEUNE ISP',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF3949AB)),
              ),
              const SizedBox(height: 6),
              const Text('Gestión de Soporte y Diagnóstico', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Correo Institucional',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3949AB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Iniciar Sesión', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 3. DASHBOARD PRINCIPAL (METRICAS, TICKETS OFFLINE, COLA Y ASISTENTE IA)
class TeuneDashboardScreen extends StatefulWidget {
  final int userId;
  const TeuneDashboardScreen({super.key, required this.userId});

  @override
  State<TeuneDashboardScreen> createState() => _TeuneDashboardScreenState();
}

class _TeuneDashboardScreenState extends State<TeuneDashboardScreen> {
  // IP 192.168.0.5 asignada a tu máquina local según ipconfig
  final String baseUrl = kIsWeb 
      ? 'http://127.0.0.1:5000/api' 
      : 'http://192.168.0.5:5000/api';

  final String routerId = 'RT-001';
  final TextEditingController _descCtrl = TextEditingController();
  String _prioridad = 'Media';

  Map<String, dynamic>? _metrica;
  List<dynamic> _tickets = [];
  bool _loading = false;

  // Variables de control de caché y estado offline
  bool _isOffline = false;
  String _cachedAt = DateTime.now().toIso8601String();

  // Chatbot IA
  final List<Map<String, String>> _chatMensajes = [
    {
      "emisor": "bot",
      "texto": "¡Hola! Soy Teune Bot 🤖. ¿Tienes problemas de conectividad o necesitas una prórroga de pago?"
    }
  ];
  final TextEditingController _chatInputCtrl = TextEditingController();
  bool _enviandoChat = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  // Sincronizar elementos en cola pendientes
  Future<void> _procesarColaSincronizacion() async {
    final pendientes = await LocalDbService.getPendingOperations();
    for (var op in pendientes) {
      if (op['action'] == 'CREATE_TICKET') {
        try {
          final payload = jsonDecode(op['payload']);
          final res = await http.post(
            Uri.parse('$baseUrl/tickets'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 4));

          if (res.statusCode == 201) {
            final db = await LocalDbService.database;
            await db.delete('sync_queue', where: 'id_op = ?', whereArgs: [op['id_op']]);
          }
        } catch (_) {
          break; // Si falla uno, no hay enlace aún
        }
      }
    }
  }

  // Cargar métricas y tickets con fallback offline hacia SQLite
  Future<void> _cargarDatos() async {
    setState(() => _loading = true);

    // Intentar sincronizar cola previa si hay internet
    await _procesarColaSincronizacion();

    try {
      final resMetrica = await http
          .get(Uri.parse('$baseUrl/metricas/router/$routerId'))
          .timeout(const Duration(seconds: 4));

      if (resMetrica.statusCode == 200) {
        final body = jsonDecode(resMetrica.body);
        final List data = body['data'] ?? [];
        _metrica = data.isNotEmpty ? data.first : null;
      }

      final resTickets = await http
          .get(Uri.parse('$baseUrl/tickets/usuario/${widget.userId}'))
          .timeout(const Duration(seconds: 4));

      if (resTickets.statusCode == 200) {
        final body = jsonDecode(resTickets.body);
        final List remoteTickets = body['data'] ?? [];

        // Guardado local en SQLite
        await LocalDbService.saveTickets(remoteTickets, widget.userId);

        setState(() {
          _tickets = remoteTickets;
          _isOffline = false;
          _cachedAt = DateTime.now().toIso8601String();
        });
      }
    } catch (e) {
      debugPrint('Modo sin conexión detectado: rescatando tickets de SQLite ($e)');
      final localData = await LocalDbService.getLocalTickets(widget.userId);
      setState(() {
        _isOffline = true;
        _tickets = localData;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // Crear ticket (en backend o en SQLite + sync_queue)
  Future<void> _crearTicket() async {
    final desc = _descCtrl.text.trim();
    if (desc.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La descripción debe contener mínimo 10 caracteres')),
      );
      return;
    }

    final clientUuid = 'uuid_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/tickets'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_usuario': widget.userId,
          'id_router': routerId,
          'descripcion_falla': desc,
          'prioridad': _prioridad,
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 201) {
        _descCtrl.clear();
        if (mounted) Navigator.pop(context);
        await _cargarDatos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ticket registrado exitosamente en el servidor')),
          );
        }
      } else {
        throw Exception('Fallo de API');
      }
    } catch (e) {
      // Registro offline en tabla local y encolado transaccional
      await LocalDbService.insertTicketLocal(
        uuid: clientUuid,
        idUsuario: widget.userId,
        descripcion: desc,
        prioridad: _prioridad,
      );

      await LocalDbService.addToSyncQueue(
        idOp: clientUuid,
        action: 'CREATE_TICKET',
        payload: jsonEncode({
          'id_usuario': widget.userId,
          'id_router': routerId,
          'descripcion_falla': desc,
          'prioridad': _prioridad,
        }),
      );

      _descCtrl.clear();
      if (mounted) Navigator.pop(context);
      await _cargarDatos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Sin conexión: Ticket guardado localmente en cola'),
          ),
        );
      }
    }
  }

  // Eliminación de Ticket (Baja Lógica en servidor y base local)
  Future<void> _eliminarTicket(dynamic ticket) async {
    final int? idTicket = ticket['id_ticket'];
    final String? clientUuid = ticket['client_uuid'];

    try {
      if (idTicket != null) {
        final res = await http.delete(Uri.parse('$baseUrl/tickets/$idTicket'));
        if (res.statusCode == 200) {
          await _cargarDatos();
          return;
        }
      }
    } catch (_) {}

    // Si está offline o falló la conexión remota, se borra de SQLite
    final db = await LocalDbService.database;
    if (idTicket != null) {
      await db.delete('tickets', where: 'id_ticket = ?', whereArgs: [idTicket]);
    } else if (clientUuid != null) {
      await db.delete('tickets', where: 'client_uuid = ?', whereArgs: [clientUuid]);
      await db.delete('sync_queue', where: 'id_op = ?', whereArgs: [clientUuid]);
    }
    await _cargarDatos();
  }

  // Cierre de sesión con purgado total
  Future<void> _handleLogout() async {
    await SecureStorageService.clearAll();
    await LocalDbService.purgeDatabase();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginView()),
      (route) => false,
    );
  }

  Widget _buildBadgeAntiguedad() {
    final cacheDate = DateTime.tryParse(_cachedAt) ?? DateTime.now();
    final difference = DateTime.now().difference(cacheDate).inMinutes;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _isOffline ? Colors.orange.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isOffline ? Colors.orange : Colors.green,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isOffline ? Icons.cloud_off : Icons.cloud_done,
            size: 16,
            color: _isOffline ? Colors.orange.shade800 : Colors.green.shade800,
          ),
          const SizedBox(width: 6),
          Text(
            _isOffline
                ? (difference == 0 ? 'Sin conexión (hace un momento)' : 'Sin conexión (hace $difference min)')
                : (difference == 0 ? 'Conectado (en línea)' : 'Actualizado hace $difference min'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _isOffline ? Colors.orange.shade800 : Colors.green.shade800,
            ),
          ),
        ],
      ),
    );
  }

  void _abrirModalChatbot() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SizedBox(
            height: 480,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.smart_toy, color: Color(0xFF3949AB)),
                        SizedBox(width: 8),
                        Text('Teune Bot - Soporte IA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _chatMensajes.length,
                    itemBuilder: (_, i) => Align(
                      alignment: _chatMensajes[i]['emisor'] == 'bot' ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: _chatMensajes[i]['emisor'] == 'bot' ? Colors.grey.shade200 : const Color(0xFF3949AB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _chatMensajes[i]['texto'] ?? '',
                          style: TextStyle(
                            color: _chatMensajes[i]['emisor'] == 'bot' ? Colors.black87 : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_enviandoChat) const LinearProgressIndicator(color: Color(0xFF3949AB)),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatInputCtrl,
                        decoration: InputDecoration(
                          hintText: 'Escribe tu consulta...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        onSubmitted: (_) => _enviarChat(setModalState),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: const Color(0xFF3949AB),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 18),
                        onPressed: () => _enviarChat(setModalState),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enviarChat(StateSetter setModalState) async {
    final txt = _chatInputCtrl.text.trim();
    if (txt.isEmpty || _enviandoChat) return;

    setModalState(() {
      _chatMensajes.add({"emisor": "user", "texto": txt});
      _enviandoChat = true;
      _chatInputCtrl.clear();
    });

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/chatbot'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_usuario': widget.userId, 'mensaje': txt}),
      ).timeout(const Duration(seconds: 5));

      final data = jsonDecode(res.body);
      setModalState(() {
        _chatMensajes.add({"emisor": "bot", "texto": data['respuesta'] ?? 'Sin respuesta'});
      });
    } catch (_) {
      setModalState(() {
        _chatMensajes.add({"emisor": "bot", "texto": "No hay conexión con el servidor para usar el chatbot."});
      });
    } finally {
      setModalState(() => _enviandoChat = false);
    }
  }

  void _abrirModalTicket() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nuevo Ticket de Soporte', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción de la falla (mínimo 10 caracteres)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _prioridad,
              items: ['Baja', 'Media', 'Alta'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (val) => setState(() => _prioridad = val!),
              decoration: const InputDecoration(labelText: 'Prioridad', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF3949AB),
                foregroundColor: Colors.white,
              ),
              onPressed: _crearTicket,
              child: const Text('Guardar Ticket'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Teune Móvil - Diagnóstico'),
        backgroundColor: const Color(0xFF3949AB),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.smart_toy_outlined), tooltip: 'Asistente IA', onPressed: _abrirModalChatbot),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refrescar', onPressed: _cargarDatos),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Cerrar Sesión', onPressed: _handleLogout),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF3949AB),
        foregroundColor: Colors.white,
        onPressed: _abrirModalTicket,
        child: const Icon(Icons.add_comment),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(child: _buildBadgeAntiguedad()),
                  const SizedBox(height: 16),
                  const Text('Estado de Red (Telemetría)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _metricaItem('Bajada', '${_metrica?['velocidad_bajada'] ?? 85.5} Mbps', Icons.download, Colors.blue),
                          _metricaItem('Subida', '${_metrica?['velocidad_subida'] ?? 20.0} Mbps', Icons.upload, Colors.green),
                          _metricaItem('Latencia', '${_metrica?['latencia_ms'] ?? 14.2} ms', Icons.timer, Colors.orange),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Mis Tickets Registrados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_tickets.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No hay tickets registrados en local ni en el servidor.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ..._tickets.map((t) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFE8EAF6),
                            child: Text(
                              '${t['id_ticket'] ?? 'Off'}',
                              style: const TextStyle(color: Color(0xFF3949AB), fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(t['descripcion_falla'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Estado: ${t['estado'] ?? 'Pendiente'} | Prioridad: ${t['prioridad'] ?? 'Media'}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _eliminarTicket(t),
                          ),
                        ),
                      ))
                ],
              ),
            ),
    );
  }

  Widget _metricaItem(String t, String v, IconData i, Color c) {
    return Column(
      children: [
        Icon(i, color: c, size: 26),
        const SizedBox(height: 4),
        Text(t, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}