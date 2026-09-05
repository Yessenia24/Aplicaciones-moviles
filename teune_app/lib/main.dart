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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
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
      body: Center(child: CircularProgressIndicator(color: Colors.indigo)),
    );
  }
}

// PANTALLA DE INICIO DE SESIÓN
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
    // Simula autenticación y guarda en el almacenamiento seguro cifrado
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_tethering, size: 75, color: Colors.indigo),
              const SizedBox(height: 12),
              const Text(
                'TEUNE ISP',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.indigo),
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
                    backgroundColor: Colors.indigo,
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

// DASHBOARD PRINCIPAL (METRICAS, TICKETS OFFLINE, COLA Y PURGADO)
class TeuneDashboardScreen extends StatefulWidget {
  final int userId;
  const TeuneDashboardScreen({super.key, required this.userId});

  @override
  State<TeuneDashboardScreen> createState() => _TeuneDashboardScreenState();
}

class _TeuneDashboardScreenState extends State<TeuneDashboardScreen> {
  final String baseUrl = kIsWeb ? 'http://127.0.0.1:5000/api' : 'http://192.168.0.6:5000/api';
  final String routerId = 'RT-001';
  final TextEditingController _descCtrl = TextEditingController();
  String _prioridad = 'Media';

  Map<String, dynamic>? _metrica;
  List<dynamic> _tickets = [];
  bool _loading = false;

  // Variables de control de caché y estado offline
  bool _isOffline = false;
  String _cachedAt = DateTime.now().toIso8601String();

  // Chatbot
  final List<Map<String, String>> _chatMensajes = [
    {"emisor": "bot", "texto": "¡Hola! Soy Teune Bot 🤖. ¿En qué te ayudo hoy?"}
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
          break; // Si falla uno, no hay internet aún
        }
      }
    }
  }

  // Cargar métricas y tickets con fallback offline
  Future<void> _cargarDatos() async {
    setState(() => _loading = true);

    // Intentar sincronizar cola previa si hay internet
    await _procesarColaSincronizacion();

    try {
      final resMetrica = await http
          .get(Uri.parse('$baseUrl/metricas/router/$routerId'))
          .timeout(const Duration(seconds: 5));

      if (resMetrica.statusCode == 200) {
        final body = jsonDecode(resMetrica.body);
        final List data = body['data'] ?? [];
        _metrica = data.isNotEmpty ? data.first : null;
      }

      final resTickets = await http
          .get(Uri.parse('$baseUrl/tickets/usuario/${widget.userId}'))
          .timeout(const Duration(seconds: 5));

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
      debugPrint('Modo sin conexión: rescatando de SQLite');
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
        const SnackBar(content: Text('Mínimo 10 caracteres')),
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
      } else {
        throw Exception('Fallo de API');
      }
    } catch (e) {
      // Registro offline en tabla local y encolado
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
        color: _isOffline ? Colors.orange.shade100 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isOffline ? Colors.orange.shade700 : Colors.green.shade700,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isOffline ? Icons.cloud_off : Icons.cloud_done,
            size: 16,
            color: _isOffline ? Colors.orange.shade900 : Colors.green.shade900,
          ),
          const SizedBox(width: 6),
          Text(
            _isOffline
                ? 'Sin conexión (hace $difference min)'
                : 'Actualizado hace $difference min',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _isOffline ? Colors.orange.shade900 : Colors.green.shade900,
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
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SizedBox(
            height: 450,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Asistente IA Teune', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _chatMensajes[i]['emisor'] == 'bot' ? Colors.grey.shade200 : Colors.indigo.shade500,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _chatMensajes[i]['texto'] ?? '',
                          style: TextStyle(color: _chatMensajes[i]['emisor'] == 'bot' ? Colors.black87 : Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_enviandoChat) const LinearProgressIndicator(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatInputCtrl,
                        decoration: const InputDecoration(hintText: 'Escribe tu duda...'),
                        onSubmitted: (_) => _enviarChat(setModalState),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.send), onPressed: () => _enviarChat(setModalState)),
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
        _chatMensajes.add({"emisor": "bot", "texto": "No hay conexión para usar el chatbot."});
      });
    } finally {
      setModalState(() => _enviandoChat = false);
    }
  }

  void _abrirModalTicket() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nuevo Ticket', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Descripción')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _prioridad,
              items: ['Baja', 'Media', 'Alta'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (val) => setState(() => _prioridad = val!),
              decoration: const InputDecoration(labelText: 'Prioridad'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: _crearTicket,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teune Móvil'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.smart_toy_outlined), onPressed: _abrirModalChatbot),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Cerrar Sesión', onPressed: _handleLogout),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        onPressed: _abrirModalTicket,
        child: const Icon(Icons.add),
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
                  const Text('Estado de Red (Telemetría)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
                  const Text('Tickets de Soporte', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_tickets.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No hay tickets'))),
                  ..._tickets.map((t) => Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${t['id_ticket'] ?? 'Off'}')),
                          title: Text(t['descripcion_falla'] ?? ''),
                          subtitle: Text('Estado: ${t['estado'] ?? 'Pendiente'} | ${t['prioridad'] ?? 'Media'}'),
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
        Icon(i, color: c),
        const SizedBox(height: 4),
        Text(t, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}