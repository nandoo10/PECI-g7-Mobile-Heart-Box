import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SessionManager.init();
  runApp(const MyApp());
}

////////////////////////////////////////////////////
/// 💾 GESTOR DE SESSÃO
////////////////////////////////////////////////////
class SessionManager {
  static late SharedPreferences prefs;
  static bool hasActiveSession = false;
  static String activityType = "Bicicleta";
  static DateTime? startTime;
  static List<double> temps = [];
  static List<int> bpms = [];
  static double lastLat = 39.3999;
  static double lastLon = -8.2245;
  static List<LatLng> route = [];
  static double distance = 0.0;
  static String serverIp = "20.220.169.18";

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    hasActiveSession = prefs.getBool('hasActiveSession') ?? false;
    activityType = prefs.getString('activityType') ?? "Bicicleta";
    String? st = prefs.getString('startTime');
    if (st != null) startTime = DateTime.parse(st);

    String? tempsJson = prefs.getString('temps');
    if (tempsJson != null) {
      List<dynamic> decoded = jsonDecode(tempsJson);
      temps = decoded.map((e) => (e as num).toDouble()).toList();
    }

    String? bpmsJson = prefs.getString('bpms');
    if (bpmsJson != null) {
      List<dynamic> decoded = jsonDecode(bpmsJson);
      bpms = decoded.map((e) => (e as num).toInt()).toList();
    }

    String? routeJson = prefs.getString('route');
    if (routeJson != null) {
      List<dynamic> decodedRoute = jsonDecode(routeJson);
      route = decodedRoute
          .map((e) => LatLng(
              (e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()))
          .toList();
    }

    distance = prefs.getDouble('distance') ?? 0.0;
    lastLat = prefs.getDouble('lastLat') ?? 39.3999;
    lastLon = prefs.getDouble('lastLon') ?? -8.2245;
  }

  static Future<void> setServerIp(String ip) async {
    serverIp = ip;
    await prefs.setString('serverIp', ip);
  }

  static Future<void> start(String type) async {
    hasActiveSession = true;
    activityType = type;
    startTime = DateTime.now();
    temps = [];
    bpms = [];
    route = [];
    distance = 0.0;
    await prefs.setBool('hasActiveSession', true);
    await prefs.setString('activityType', type);
    await prefs.setString('startTime', startTime!.toIso8601String());
    await prefs.setString('temps', '[]');
    await prefs.setString('bpms', '[]');
    await prefs.setString('route', '[]');
    await prefs.setDouble('distance', 0.0);
  }

  static Future<void> saveProgress(List<double> t, List<int> b, double la,
      double lo, List<LatLng> r, double d) async {
    temps = List.from(t);
    bpms = List.from(b);
    lastLat = la;
    lastLon = lo;
    route = List.from(r);
    distance = d;
    await prefs.setString('temps', jsonEncode(temps));
    await prefs.setString('bpms', jsonEncode(bpms));
    await prefs.setDouble('lastLat', la);
    await prefs.setDouble('lastLon', lo);
    await prefs.setString(
        'route',
        jsonEncode(route
            .map((p) => {'lat': p.latitude, 'lon': p.longitude})
            .toList()));
    await prefs.setDouble('distance', distance);
  }

  static Future<void> clear() async {
    hasActiveSession = false;
    startTime = null;
    temps = [];
    bpms = [];
    route = [];
    distance = 0.0;
    await prefs.clear();
  }

  static int get elapsedSeconds {
    if (startTime == null) return 0;
    return DateTime.now().difference(startTime!).inSeconds;
  }

  static Future<void> adjustStartTimeForPause(int currentSeconds) async {
    startTime = DateTime.now().subtract(Duration(seconds: currentSeconds));
    await prefs.setString('startTime', startTime!.toIso8601String());
  }
}

class AppColors {
  static const primary = Color(0xFF00D1FF);
  static const secondary = Color(0xFF6366F1);
  static const background = Color(0xFF0B0E14);
  static const surface = Color(0xFF1E293B);
  static const success = Color(0xFF10B981);
  static const danger = Color(0xFFEF4444);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mobile Heart Box',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary, brightness: Brightness.dark),
        cardTheme: CardThemeData(
            color: AppColors.surface.withOpacity(0.7),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24))),
      ),
      home: SessionManager.hasActiveSession
          ? MonitorScreen(
              atividade: SessionManager.activityType, retomando: true)
          : const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
              top: -100,
              right: -100,
              child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.1)))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.primary.withOpacity(0.2),
                                blurRadius: 40,
                                spreadRadius: 10)
                          ]),
                      child: const Icon(Icons.monitor_heart_rounded,
                          size: 100, color: AppColors.primary)),
                  const SizedBox(height: 50),
                  const Text('Mobile Heart Box',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.5)),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 65,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushReplacement(context,
                          MaterialPageRoute(builder: (_) => const ActivityMenuScreen())),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      child: const Text('ACEDER AO SISTEMA',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityMenuScreen extends StatefulWidget {
  const ActivityMenuScreen({super.key});
  @override
  State<ActivityMenuScreen> createState() => _ActivityMenuScreenState();
}

class _ActivityMenuScreenState extends State<ActivityMenuScreen> {
  int _currentIndex = 1;
  bool isLoading = false;
  List<ActivityData> activitiesList = [];

  @override
  void initState() {
    super.initState();
    buscarHistoricoDoPC();
  }

  Future<void> buscarHistoricoDoPC() async {
    setState(() => isLoading = true);
    try {
      final url =
          Uri.parse('http://${SessionManager.serverIp}:1880/lista-atividades');
      final response =
          await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        List<ActivityData> listaFinal = [];
        for (var item in data) {
          try {
            List<double> tempsExtraidas = [];
            var rawTemps = item['temperatures'];
            if (rawTemps is List) {
              tempsExtraidas =
                  rawTemps.map((e) => (e as num).toDouble()).toList();
            } else if (rawTemps is String) {
              try {
                var decoded = jsonDecode(rawTemps);
                if (decoded is List)
                  tempsExtraidas =
                      decoded.map((e) => (e as num).toDouble()).toList();
              } catch (_) {
                tempsExtraidas = rawTemps
                    .split(',')
                    .map((e) => double.tryParse(e) ?? 0.0)
                    .toList();
              }
            }

            List<LatLng> routeExtraida = [];
            var rawRoute = item['route'];
            if (rawRoute != null) {
              try {
                dynamic decoded = rawRoute;
                if (rawRoute is String) decoded = jsonDecode(rawRoute);
                if (decoded is List) {
                  routeExtraida = decoded
                      .map((e) => LatLng((e['lat'] as num).toDouble(),
                          (e['lon'] as num).toDouble()))
                      .toList();
                }
              } catch (e) {
                print("Erro rota: $e");
              }
            }

            double distExtraida = 0.0;
            if (item['distance'] != null) {
              distExtraida =
                  double.tryParse(item['distance'].toString()) ?? 0.0;
            }

            List<int> bpmExtraidos = [];
            var rawBpm = item['bpm_history'];
            if (rawBpm is List) {
              bpmExtraidos = rawBpm.map((e) => (e as num).toInt()).toList();
            } else if (rawBpm is String) {
              try {
                var decoded = jsonDecode(rawBpm);
                if (decoded is List)
                  bpmExtraidos =
                      decoded.map((e) => (e as num).toInt()).toList();
              } catch (_) {
                bpmExtraidos = rawBpm
                    .split(',')
                    .map((e) => int.tryParse(e) ?? 0)
                    .toList();
              }
            }

            listaFinal.add(ActivityData(
              id: item['time'],
              type: item['type'] ?? "Atividade",
              duration: item['duracao_segundos'] ?? 0,
              temperatures: tempsExtraidas,
              route: routeExtraida,
              distance: distExtraida,
              min: double.tryParse(item['temp_minima']?.toString() ?? "0") ??
                  0.0,
              avg: double.tryParse(item['temp_media']?.toString() ?? "0") ??
                  0.0,
              max: double.tryParse(item['temp_maxima']?.toString() ?? "0") ??
                  0.0,
              bpmReadings: bpmExtraidos,
            ));
          } catch (e) {
            print("Erro ao processar item do histórico: $e");
          }
        }
        if (mounted) setState(() => activitiesList = listaFinal);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Erro de ligação ao PC")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _mostrarDialogoRetomar() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Atividade Pendente"),
        content: const Text("Deseja continuar ou começar uma nova?"),
        actions: [
          TextButton(
              onPressed: () {
                SessionManager.clear();
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ActivityScreen()));
              },
              child: const Text("NOVA",
                  style: TextStyle(color: AppColors.danger))),
          ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MonitorScreen(
                            atividade: SessionManager.activityType,
                            retomando: true)));
              },
              child: const Text("CONTINUAR")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ─────────────────────────────────────────────────────────────────────────
    // ALTERAÇÃO 1: Aba de Configurações substituída pelo Manual de Utilizador
    // ─────────────────────────────────────────────────────────────────────────
    final List<Widget> pages = [
      const UserManualScreen(),
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                if (SessionManager.hasActiveSession) {
                  _mostrarDialogoRetomar();
                } else {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ActivityScreen()));
                }
              },
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withOpacity(0.15),
                          blurRadius: 30)
                    ]),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 80, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 20),
            const Text("INICIAR MONITORIZAÇÃO",
                style:
                    TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ],
        ),
      ),
      RefreshIndicator(
        onRefresh: buscarHistoricoDoPC,
        child: ActivityLogScreen(
            activities: activitiesList, onRefresh: buscarHistoricoDoPC),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0
            ? "Configurações"
            : _currentIndex == 1
                ? "Dashboard"
                : "Histórico"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 2) buscarHistoricoDoPC();
        },
        backgroundColor: const Color(0xFF161B22),
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.white24,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Configurações'),
          BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_filled, size: 40),
              label: 'Monitorização'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'Histórico'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURAÇÕES & MANUAL DO UTILIZADOR (VERSÃO CORRIGIDA)
// ─────────────────────────────────────────────────────────────────────────────
class UserManualScreen extends StatefulWidget {
  const UserManualScreen({super.key});

  @override
  State<UserManualScreen> createState() => _UserManualScreenState();
}

class _UserManualScreenState extends State<UserManualScreen> {
  bool _showManualContent = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.15),
                  AppColors.secondary.withOpacity(0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.settings_suggest_rounded,
                      color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Painel de Configurações",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Mobile Heart Box",
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          // Botão 1: Configurar Placa via QR Code
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QRScannerScreen())),
              icon: const Icon(Icons.qr_code_scanner, size: 22),
              label: const Text("Configurar via QR code",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          const SizedBox(height: 15),

          // Botão 2: Manual do utilizador expansível
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showManualContent = !_showManualContent;
                });
              },
              icon: Icon(_showManualContent ? Icons.menu_book_rounded : Icons.menu_book_outlined, size: 22),
              label: const Text("Manual do utilizador",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    // CORREÇÃO: Alterado de Border.all para BorderSide
                    side: const BorderSide(color: Colors.white10)),
              ),
            ),
          ),

          // Conteúdo do Manual do Utilizador (Apenas mostra se _showManualContent for true)
          if (_showManualContent) ...[
            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 15),
              child: Text(
                "Instruções do Sistema:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
            
            _buildStep(
              number: 1,
              icon: Icons.wifi_tethering_rounded,
              color: const Color(0xFF00D1FF),
              title: "Ligar o Access Point Wi-Fi",
              description:
                  "Ative um ponto de acesso Wi-Fi (hotspot ou router) que permita a ligação das caixas e do seu telemóvel ao mesmo sistema.",
            ),
            _buildStep(
              number: 2,
              icon: Icons.smartphone_rounded,
              color: const Color(0xFF6366F1),
              title: "Ligar o telemóvel ao Access Point",
              description:
                  "Certifique-se de que o seu telemóvel está ligado à mesma rede Wi-Fi do Access Point, caso não esteja já conectado automaticamente.",
            ),
            _buildStep(
              number: 3,
              icon: Icons.qr_code_scanner_rounded,
              color: const Color(0xFF10B981),
              title: "Scan do QR Code da caixa",
              description:
                  "Utilize o botão acima para efetuar o scan do QR Code presente na caixa. Isto inicia a configuração e emparelhamento do sistema.",
            ),
            _buildStep(
              number: 4,
              icon: Icons.developer_board_rounded,
              color: const Color(0xFFF59E0B),
              title: "Verificar conectividade das placas",
              description:
                  "Confirme que as placas/dispositivos estabeleceram ligação. Caso alguma não responda, repita o scan do QR Code para tentar novamente.",
              isWarning: true,
              warningText: "Se alguma falhar → repetir scan do QR Code",
            ),
            _buildStep(
              number: 5,
              icon: Icons.play_circle_filled_rounded,
              color: const Color(0xFF00D1FF),
              title: "Iniciar a atividade",
              description:
                  "Aceda ao Dashboard (aba central) e prima o botão de iniciar. Selecione o tipo de atividade e confirme para começar a monitorização.",
            ),
            _buildStep(
              number: 6,
              icon: Icons.monitor_heart_rounded,
              color: const Color(0xFFEF4444),
              title: "Verificar todas as funcionalidades",
              description:
                  "Durante a atividade, confirme que todos os sensores estão ativos:",
              extras: const [
                _ManualExtra(icon: Icons.favorite, label: "Frequência cardíaca (BPM)"),
                _ManualExtra(icon: Icons.thermostat_rounded, label: "Temperatura corporal"),
                _ManualExtra(icon: Icons.gps_fixed, label: "GPS"),
                _ManualExtra(icon: Icons.sensor_occupied_rounded, label: "Sensor de proximidade"),
                _ManualExtra(icon: Icons.warning_amber_rounded, label: "Sensor de quedas"),
              ],
            ),
            _buildStep(
              number: 7,
              icon: Icons.check_circle_rounded,
              color: const Color(0xFF10B981),
              title: "Tudo operacional — Boa atividade!",
              description:
                  "Se todos os sistemas estiverem ativos, a atividade pode decorrer normalmente. Desfrute da Mobile Heart Box!",
            ),
            _buildStep(
              number: 8,
              icon: Icons.refresh_rounded,
              color: const Color(0xFFF59E0B),
              title: "Problemas? Tente reconectar",
              description:
                  "Se alguma funcionalidade não responder, aguarde alguns instantes. Caso persista, utilize o botão de QR Code na barra superior durante a atividade para restabelecer a ligação sem precisar de a terminar.",
              isWarning: true,
              warningText: "Use o ícone QR na atividade para reconectar sem parar",
              isLast: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep({
    required int number,
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    bool isWarning = false,
    String? warningText,
    List<_ManualExtra>? extras,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.5), width: 1.5),
              ),
              child: Center(
                child: Text(
                  "$number",
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ),
            if (!isLast)
              Container(width: 2, height: 20, color: Colors.white10),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: isWarning ? color.withOpacity(0.4) : Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(description, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
                if (extras != null) ...[
                  const SizedBox(height: 10),
                  // CORREÇÃO: Forçada a tipagem explicática (_ManualExtra e) para evitar erro de Object?
                  ...extras.map((_ManualExtra e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(e.icon, color: AppColors.primary, size: 16),
                            const SizedBox(width: 8),
                            Text(e.label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      )),
                ],
                if (isWarning && warningText != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: color, size: 15),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(warningText, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ManualExtra {
  final IconData icon;
  final String label;
  const _ManualExtra({required this.icon, required this.label});
}

// ─────────────────────────────────────────────────────────────────────────────
// Ecrã de seleção de atividade (sem alterações)
// ─────────────────────────────────────────────────────────────────────────────
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String atividade = 'Bicicleta';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Perfil'), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            _profileTile('Bicicleta', Icons.directions_bike_rounded),
            const Spacer(),
            SizedBox(
                width: double.infinity,
                height: 65,
                child: ElevatedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                MonitorScreen(atividade: atividade))),
                    child: const Text("INICIAR",
                        style: TextStyle(fontWeight: FontWeight.bold)))),
          ],
        ),
      ),
    );
  }

  Widget _profileTile(String t, IconData i) {
    bool sel = atividade == t;
    return GestureDetector(
      onTap: () => setState(() => atividade = t),
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
            color: sel ? AppColors.primary.withOpacity(0.1) : AppColors.surface,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
                color: sel ? AppColors.primary : Colors.transparent, width: 2)),
        child: Row(children: [
          Icon(i, color: sel ? AppColors.primary : Colors.white60, size: 30),
          const SizedBox(width: 25),
          Text(t,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          if (sel) const Icon(Icons.check_circle_rounded, color: AppColors.primary)
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ecrã de monitorização — ALTERAÇÃO 2: botão QR na AppBar
// ─────────────────────────────────────────────────────────────────────────────
class MonitorScreen extends StatefulWidget {
  final String atividade;
  final bool retomando;

  const MonitorScreen(
      {super.key, required this.atividade, this.retomando = false});
  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  MqttServerClient? client;
  List<double> allTemps = [];
  List<int> allBpms = [];
  double currentTemp = 0;

  double lat = 39.3999;
  double lon = -8.2245;
  List<LatLng> route = [];
  double distance = 0.0;
  bool firstGpsLock = false;

  bool hasGpsSignal = false;
  bool connected = false;
  bool isPaused = false;
  late Timer timer;
  int seconds = 0;
  bool showThermal = false;
  bool showMap = false;

  List<int>? rawThermalData;

  final MapController _mapController = MapController();

  bool isShowingFallAlert = false;

  String proximityStatus = "CAMINHO_LIVRE";
  bool blinkState = true;
  Timer? blinkTimer;

  List<double> ecgPoints = [];
  int currentBpm = 0;
  bool heartBlinkState = false;
  Timer? heartBlinkTimer;
  Timer? bpmTimeoutTimer;
  static const int ecgMaxPoints = 100;

  int _bpmCalibrationCounter = 0;

  String connectionMessage = "";
  Color connectionColor = Colors.transparent;
  bool isRecovering = false;
  bool fatalError = false;
  Timer? _networkCheckTimer;
  int _disconnectSeconds = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.retomando) {
      SessionManager.start(widget.atividade);
    } else {
      _bpmCalibrationCounter = 7;
      allTemps = SessionManager.temps;
      allBpms = SessionManager.bpms;
      lat = SessionManager.lastLat;
      lon = SessionManager.lastLon;
      route = SessionManager.route;
      distance = SessionManager.distance;
      seconds = SessionManager.elapsedSeconds;
      if (route.isNotEmpty) {
        firstGpsLock = true;
        hasGpsSignal = true;
      }
    }
    connectMQTT();
    _startNetworkMonitor();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !isPaused) {
        setState(() {
          seconds = SessionManager.elapsedSeconds;
        });
        SessionManager.saveProgress(
            allTemps, allBpms, lat, lon, route, distance);
      }
    });
    blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (mounted && proximityStatus == "OBSTACULO_PERTO") {
        setState(() => blinkState = !blinkState);
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    blinkTimer?.cancel();
    heartBlinkTimer?.cancel();
    bpmTimeoutTimer?.cancel();
    _networkCheckTimer?.cancel();
    client?.disconnect();
    super.dispose();
  }

  void _startNetworkMonitor() {
    _networkCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || fatalError) return;
      final bool isConnected =
          client?.connectionStatus?.state == MqttConnectionState.connected;
      if (!isConnected) {
        _disconnectSeconds += 2;
        if (_disconnectSeconds >= 120) {
          setState(() {
            fatalError = true;
            isRecovering = false;
            connectionMessage =
                "Ligação perdida há mais de 2 min. Configure via QR Code.";
            connectionColor = Colors.red;
          });
          _networkCheckTimer?.cancel();
          client?.disconnect();
        } else if (!isRecovering) {
          setState(() {
            isRecovering = true;
            connectionMessage = "Conexão Perdida. A tentar restabelecer...";
            connectionColor = Colors.orange;
          });
        }
      } else {
        _disconnectSeconds = 0;
        if (isRecovering) {
          setState(() {
            isRecovering = false;
            connectionMessage = "Ligação restabelecida com sucesso";
            connectionColor = Colors.green;
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !isRecovering && !fatalError) {
              setState(() => connectionMessage = "");
            }
          });
        }
      }
    });
  }

  void _triggerHeartBlink() {
    heartBlinkTimer?.cancel();
    setState(() => heartBlinkState = true);
    heartBlinkTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => heartBlinkState = false);
    });
  }

  Future<void> connectMQTT() async {
    client = MqttServerClient(SessionManager.serverIp,
        'flutter_${DateTime.now().millisecondsSinceEpoch}');
    client!.autoReconnect = true;
    try {
      await client!.connect();
      setState(() => connected = true);
      client!.subscribe('heartbox/sensor/thermal', MqttQos.atMostOnce);
      client!.subscribe('heartbox/cam/thermal_raw', MqttQos.atMostOnce);
      client!.subscribe('heartbox/gps/coords', MqttQos.atMostOnce);
      client!.subscribe('heartbox/alerts/fall', MqttQos.atMostOnce);
      client!.subscribe('heartbox/sensor/proximity', MqttQos.atMostOnce);
      client!.subscribe('heartbox/heart/ecg', MqttQos.atMostOnce);
      client!.subscribe('heartbox/heart/bpm', MqttQos.atMostOnce);

      client!.updates?.listen((c) {
        final MqttPublishMessage recMess =
            c[0].payload as MqttPublishMessage;
        final String topic = c[0].topic;

        if (topic == 'heartbox/cam/thermal_raw') {
          if (mounted && showThermal) {
            setState(() {
              rawThermalData = recMess.payload.message;
            });
          }
          return;
        }

        final String payload =
            String.fromCharCodes(recMess.payload.message);
        if (!mounted) return;

        if (topic == 'heartbox/sensor/proximity') {
          setState(() {
            proximityStatus = payload.trim();
          });
        }

        if (topic == 'heartbox/alerts/fall' && payload.contains("ALERTA")) {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
          _mostrarAlertaQueda();
        }

        if (isPaused) return;
        setState(() {
          if (topic == 'heartbox/sensor/thermal') {
          double parsedTemp = double.tryParse(payload) ?? currentTemp;
          if (parsedTemp <= 50.0) {
            currentTemp = parsedTemp;
            allTemps.add(currentTemp);
          }
        } else if (topic == 'heartbox/gps/coords') {
            if (payload == "Sem sinal GPS" ||
                payload.contains("não detetado") ||
                payload.isEmpty) {
              hasGpsSignal = false;
            } else {
              final coords = payload.split(',');
              if (coords.length == 2) {
                hasGpsSignal = true;
                double newLat = double.tryParse(coords[0]) ?? lat;
                double newLon = double.tryParse(coords[1]) ?? lon;
                LatLng newPoint = LatLng(newLat, newLon);
                if (!firstGpsLock) {
                  firstGpsLock = true;
                  lat = newLat;
                  lon = newLon;
                  route.add(newPoint);
                } else if (newLat != lat || newLon != lon) {
                  distance += const Distance()
                      .distance(LatLng(lat, lon), newPoint);
                  lat = newLat;
                  lon = newLon;
                  route.add(newPoint);
                }
                if (showMap)
                  _mapController.move(newPoint, _mapController.camera.zoom);
              } else {
                hasGpsSignal = false;
              }
            }
          } else if (topic == 'heartbox/heart/ecg') {
            double val = double.tryParse(payload) ?? 0.0;
            ecgPoints.add(val);
            if (ecgPoints.length > ecgMaxPoints) {
              ecgPoints.removeAt(0);
            }
          } else if (topic == 'heartbox/heart/bpm') {
            int newBpm = int.tryParse(payload) ?? 0;
            if (_bpmCalibrationCounter < 7) {
              _bpmCalibrationCounter++;
              return;
            }
            currentBpm = newBpm;
            if (newBpm > 0) {
              allBpms.add(newBpm);
              _triggerHeartBlink();
            }
            bpmTimeoutTimer?.cancel();
            bpmTimeoutTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => currentBpm = 0);
            });
          }
        });
      });
    } catch (e) {
      print(e);
      if (mounted) {
        setState(() {
          fatalError = true;
          connectionMessage =
              "Não foi possível restabelecer ligação. Leia o QR code novamente.";
          connectionColor = Colors.red;
        });
      }
    }
  }

  void _mostrarAlertaQueda() {
    if (isShowingFallAlert) return;
    isShowingFallAlert = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.danger,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 30),
            SizedBox(width: 10),
            Text("QUEDA DETETADA!",
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("Precisa de ajuda?",
            style: TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2)),
                onPressed: () {
                  isShowingFallAlert = false;
                  Navigator.pop(ctx);
                },
                child: const Text("NÃO",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.danger),
                onPressed: () {
                  Navigator.pop(ctx);
                  _mostrarDialogoLigar112();
                },
                child: const Text("SIM",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _mostrarDialogoLigar112() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Emergência"),
        content: const Text("Precisa de ligar ao 112?"),
        actions: [
          TextButton(
            onPressed: () {
              isShowingFallAlert = false;
              Navigator.pop(ctx);
            },
            child: const Text("NÃO"),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              isShowingFallAlert = false;
              Navigator.pop(ctx);
              final Uri url = Uri.parse('tel:960254309');
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
            child: const Text("SIM"),
          ),
        ],
      ),
    );
  }

  Future<bool> _onWillPop() async {
    bool? abandonar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Deseja abandonar atividade?"),
        content: const Text(
            "O progresso atual não será guardado no histórico."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("CONTINUAR")),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () {
                SessionManager.clear();
                Navigator.pop(ctx, true);
              },
              child: const Text("TERMINAR")),
        ],
      ),
    );
    return abandonar ?? false;
  }

  Future<void> finishActivity() async {
    setState(() => isPaused = true);
    final TextEditingController nameCtrl =
        TextEditingController(text: widget.atividade);
    bool? salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Finalizar Sessão"),
        content: TextField(
            controller: nameCtrl,
            decoration:
                const InputDecoration(labelText: "Nome do percurso")),
        actions: [
          TextButton(
              onPressed: () {
                setState(() => isPaused = false);
                Navigator.pop(ctx, false);
              },
              child: const Text("VOLTAR")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("GUARDAR")),
        ],
      ),
    );

    if (salvar == true) {
      try {
        await http.post(
          Uri.parse('http://${SessionManager.serverIp}:1880/guardar'),
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            "type": nameCtrl.text,
            "duration": seconds,
            "temperatures": allTemps,
            "distance": distance,
            "route": route
                .map((p) => {'lat': p.latitude, 'lon': p.longitude})
                .toList(),
            "bpm_history": allBpms,
          }),
        );
      } catch (e) {
        print(e);
      }
      SessionManager.clear();
      if (mounted)
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const ActivityMenuScreen()),
            (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final bool shouldPop = await _onWillPop();
        if (shouldPop && context.mounted)
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const ActivityMenuScreen()),
              (route) => false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.atividade),
          backgroundColor: Colors.transparent,
          actions: [
            // Botão Mapa
            IconButton(
                icon: Icon(Icons.map_rounded,
                    color: showMap ? AppColors.primary : Colors.white38),
                onPressed: () => setState(() {
                      showMap = !showMap;
                      if (showMap) showThermal = false;
                    })),
            // Botão Câmara Térmica
            IconButton(
                icon: Icon(Icons.camera_alt,
                    color: showThermal ? AppColors.primary : Colors.white38),
                onPressed: () => setState(() {
                      showThermal = !showThermal;
                      if (showThermal) showMap = false;
                    })),
            // ─────────────────────────────────────────────────────────────
            // ALTERAÇÃO 2: Botão QR Code durante a atividade
            // ─────────────────────────────────────────────────────────────
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded,
                  color: Colors.white60),
              tooltip: "Configurar Placa via QR",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const QRScannerScreen()),
                );
              },
            ),
            Padding(
                padding: const EdgeInsets.only(right: 15),
                child: Icon(Icons.circle,
                    color: connected
                        ? AppColors.success
                        : AppColors.danger,
                    size: 12)),
          ],
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (showMap || showThermal)
                      Container(
                          height: 250,
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.white10)),
                          clipBehavior: Clip.antiAlias,
                          child: showMap
                              ? _buildMapWidget()
                              : _buildThermalWidget()),
                    _buildTempAndBpmCards(),
                    const SizedBox(height: 15),
                    Row(children: [
                      _buildMiniBox(
                          "Tempo", _formatTime(seconds), Icons.timer_outlined),
                      const SizedBox(width: 15),
                      _buildProximityBox()
                    ]),
                    const SizedBox(height: 15),
                    _buildGPSStatusBox(),
                    const SizedBox(height: 20),
                    SizedBox(height: 250, child: _buildEcgChart()),
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Expanded(
                            child: SizedBox(
                                height: 60,
                                child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: isPaused
                                            ? AppColors.success
                                            : Colors.orangeAccent),
                                    onPressed: () {
                                      setState(() {
                                        isPaused = !isPaused;
                                        if (!isPaused)
                                          SessionManager
                                              .adjustStartTimeForPause(
                                                  seconds);
                                      });
                                    },
                                    icon: Icon(isPaused
                                        ? Icons.play_arrow
                                        : Icons.pause),
                                    label: Text(
                                        isPaused ? "RETOMAR" : "PAUSAR")))),
                        const SizedBox(width: 15),
                        Expanded(
                            child: SizedBox(
                                height: 60,
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.danger),
                                    onPressed: finishActivity,
                                    child: const Text("CONCLUIR",
                                        style: TextStyle(
                                            fontWeight:
                                                FontWeight.bold))))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (connectionMessage.isNotEmpty)
              Positioned(
                top: 10,
                left: 15,
                right: 15,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: connectionColor.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black45,
                            blurRadius: 10,
                            offset: Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      children: [
                        if (isRecovering)
                          const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                        if (isRecovering) const SizedBox(width: 15),
                        Expanded(
                          child: Text(
                            connectionMessage,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (fatalError)
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTempAndBpmCards() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(25)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPaused ? "TEMPERATURA (PAUSADO)" : "TEMPERATURA ATUAL",
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "${currentTemp.toStringAsFixed(1)}°C",
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: isPaused ? Colors.white24 : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(25)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("BATIMENTOS",
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Icons.favorite,
                          color: heartBlinkState
                              ? AppColors.danger
                              : AppColors.danger.withOpacity(0.3),
                          size: heartBlinkState ? 28 : 22),
                    ),
                    const SizedBox(width: 8),
                    currentBpm == 0
                        ? const Text(
                            "Não estão a\nser detetados\nbpms",
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white38,
                                height: 1.2))
                        : Text("$currentBpm bpm",
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: isPaused
                                    ? Colors.white24
                                    : AppColors.danger)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEcgChart() {
    if (ecgPoints.isEmpty) {
      return Container(
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(25)),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.monitor_heart_outlined,
                  color: Colors.white24, size: 40),
              SizedBox(height: 8),
              Text("A aguardar sinal ECG...",
                  style: TextStyle(color: Colors.white24)),
            ],
          ),
        ),
      );
    }

    final spots = ecgPoints.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    double minY = ecgPoints.reduce((a, b) => a < b ? a : b) - 100;
    double maxY = ecgPoints.reduce((a, b) => a > b ? a : b) + 100;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppColors.danger.withOpacity(0.3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 4),
            child: Text("ECG  ──────────────────────",
                style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: (maxY - minY) / 4,
                  verticalInterval: ecgMaxPoints / 5,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFF1A2A1A), strokeWidth: 1),
                  getDrawingVerticalLine: (_) =>
                      const FlLine(color: Color(0xFF1A2A1A), strokeWidth: 1),
                ),
                titlesData: const FlTitlesData(
                  leftTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: AppColors.danger,
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.danger.withOpacity(0.05)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapWidget() {
    if (!hasGpsSignal) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text("Não é possível encontrar a sua localização!",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ),
      );
    }
    return FlutterMap(
        mapController: _mapController,
        options:
            MapOptions(initialCenter: LatLng(lat, lon), initialZoom: 15),
        children: [
          TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.mobile.heartbox'),
          PolylineLayer(polylines: [
            Polyline(points: route, strokeWidth: 4, color: AppColors.danger)
          ]),
          MarkerLayer(markers: [
            Marker(
                point: LatLng(lat, lon),
                width: 50,
                height: 50,
                child: const Icon(Icons.location_on,
                    color: AppColors.danger, size: 40))
          ])
        ]);
  }

  Widget _buildProximityBox() {
    bool isDanger = proximityStatus == "OBSTACULO_PERTO";
    Color iconColor =
        isDanger ? (blinkState ? AppColors.danger : Colors.black) : AppColors.success;
    String label = isDanger ? "Perigo!" : "Livre!";
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(25)),
        child: Row(
          children: [
            Icon(Icons.directions_car_filled, color: iconColor, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Caminho",
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: iconColor))
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildThermalWidget() {
    if (rawThermalData == null || rawThermalData!.length != 3072) {
      return const Center(
          child: Text("A aguardar matriz térmica...",
              style: TextStyle(color: Colors.white38)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CustomPaint(
          size: const Size(double.infinity, double.infinity),
          painter: ThermalPainter(rawThermalData!),
        ),
      ),
    );
  }

  Widget _buildMiniBox(String l, String v, IconData i) => Expanded(
      child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(25)),
          child: Row(children: [
            Icon(i, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l,
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11)),
              Text(v,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold))
            ])
          ])));

  Widget _buildGPSStatusBox() => Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        const Icon(Icons.gps_fixed, color: AppColors.success, size: 18),
        const SizedBox(width: 15),
        Text("GPS | Dist: ${distance.toStringAsFixed(0)}m",
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.bold))
      ]));

  String _formatTime(int s) =>
      "${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}";
}

// ─────────────────────────────────────────────────────────────────────────────
// Histórico
// ─────────────────────────────────────────────────────────────────────────────
class ActivityLogScreen extends StatefulWidget {
  final List<ActivityData> activities;
  final VoidCallback onRefresh;
  const ActivityLogScreen(
      {super.key, required this.activities, required this.onRefresh});
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  Set<String> selectedIds = {};
  bool isSelectionMode = false;

  Future<void> apagarMultiplas() async {
    bool? confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text("Apagar ${selectedIds.length} atividades?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("CANCELAR")),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text("APAGAR TUDO"))
                ]));
    if (confirmar == true) {
      for (var id in selectedIds) {
        try {
          await http.delete(
              Uri.parse('http://${SessionManager.serverIp}:1880/apagar'),
              headers: {"Content-Type": "application/json"},
              body: json.encode({"time": id}));
        } catch (e) {}
      }
      widget.onRefresh();
      setState(() {
        selectedIds.clear();
        isSelectionMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: widget.activities.length,
        itemBuilder: (context, i) {
          final act = widget.activities[i];
          final isSelected = selectedIds.contains(act.id);
          return Card(
            color: isSelected
                ? AppColors.primary.withOpacity(0.2)
                : AppColors.surface,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: isSelectionMode
                  ? Checkbox(
                      value: isSelected,
                      onChanged: (_) => setState(() => isSelected
                          ? selectedIds.remove(act.id)
                          : selectedIds.add(act.id!)))
                  : const Icon(Icons.history),
              title: Text(act.type,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  "Dist: ${act.distance.toStringAsFixed(0)}m | Média: ${act.avg.toStringAsFixed(1)}°C"),
              onLongPress: () => setState(() {
                isSelectionMode = true;
                selectedIds.add(act.id!);
              }),
              onTap: () => isSelectionMode
                  ? setState(() => isSelected
                      ? selectedIds.remove(act.id)
                      : selectedIds.add(act.id!))
                  : Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ActivityDetailScreen(activity: act))),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detalhe de atividade — ALTERAÇÃO 3: mapa com tiles reais no histórico
// ─────────────────────────────────────────────────────────────────────────────
class ActivityDetailScreen extends StatelessWidget {
  final ActivityData activity;
  const ActivityDetailScreen({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    int totalSecs = activity.temperatures.length;
    double intervalX = 10.0;
    if (totalSecs <= 60) intervalX = 10.0;
    else if (totalSecs <= 300) intervalX = 60.0;
    else if (totalSecs <= 1800) intervalX = 300.0;
    else if (totalSecs <= 3600) intervalX = 600.0;
    else intervalX = 1800.0;

    double spacing = 15.0;
    if (totalSecs > 300) spacing = 5.0;
    if (totalSecs > 1800) spacing = 2.0;
    if (totalSecs > 3600) spacing = 1.0;

    double dynamicWidth = (totalSecs * spacing);
    if (dynamicWidth < MediaQuery.of(context).size.width)
      dynamicWidth = MediaQuery.of(context).size.width;

    LatLngBounds? routeBounds;
    if (activity.route.length >= 2)
      routeBounds = LatLngBounds.fromPoints(activity.route);

    final List<int> validBpms =
        activity.bpmReadings.where((b) => b > 0).toList();
    final int bpmMin = validBpms.isNotEmpty
        ? validBpms.reduce((a, b) => a < b ? a : b)
        : 0;
    final int bpmMax = validBpms.isNotEmpty
        ? validBpms.reduce((a, b) => a > b ? a : b)
        : 0;
    final double bpmAvg = validBpms.isNotEmpty
        ? validBpms.reduce((a, b) => a + b) / validBpms.length
        : 0.0;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(activity.type),
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(icon: Icon(Icons.thermostat), text: "Temperatura"),
              Tab(icon: Icon(Icons.map_outlined), text: "Percurso"),
              Tab(icon: Icon(Icons.favorite), text: "BPM"),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // ── Tab Temperatura ──────────────────────────────────────────
            Column(
              children: [
                Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _detBox("MIN", "${activity.min.toStringAsFixed(1)}°"),
                          _detBox("AVG", "${activity.avg.toStringAsFixed(1)}°"),
                          _detBox("MAX", "${activity.max.toStringAsFixed(1)}°")
                        ])),
                const Divider(color: Colors.white10),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(25)),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        width: dynamicWidth,
                        padding: const EdgeInsets.fromLTRB(10, 40, 30, 20),
                        child: activity.temperatures.isEmpty
                            ? const Center(
                                child: Text("Gráfico não disponível"))
                            : LineChart(
                                LineChartData(
                                  minX: 0,
                                  maxX: activity.temperatures.length > 1
                                      ? activity.temperatures.length.toDouble() - 1
                                      : 1,
                                  minY: (activity.min - 3).clamp(0, 100),
                                  maxY: (activity.max + 3).clamp(0, 100),
                                  gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: true,
                                      getDrawingHorizontalLine: (v) =>
                                          const FlLine(
                                              color: Colors.white10,
                                              strokeWidth: 1),
                                      getDrawingVerticalLine: (v) =>
                                          const FlLine(
                                              color: Colors.white10,
                                              strokeWidth: 1)),
                                  titlesData: FlTitlesData(
                                    leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 45,
                                            getTitlesWidget: (v, m) => Text(
                                                "${v.toInt()}°",
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white38)))),
                                    bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 30,
                                            interval: intervalX,
                                            getTitlesWidget: (v, m) {
                                              int s = v.toInt();
                                              if (s == 0)
                                                return const Text("0s",
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white38));
                                              if (s < 60)
                                                return Text("${s}s",
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white38));
                                              if (s < 3600)
                                                return Text("${s ~/ 60}m",
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white38));
                                              return Text("${s ~/ 3600}h",
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white38));
                                            })),
                                    rightTitles: const AxisTitles(
                                        sideTitles:
                                            SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(
                                        sideTitles:
                                            SideTitles(showTitles: false)),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  lineBarsData: [
                                    LineChartBarData(
                                        spots: activity.temperatures
                                            .asMap()
                                            .entries
                                            .map((e) => FlSpot(
                                                e.key.toDouble(), e.value))
                                            .toList(),
                                        isCurved: true,
                                        color: AppColors.primary,
                                        barWidth: 5,
                                        dotData: const FlDotData(show: false),
                                        belowBarData: BarAreaData(
                                            show: true,
                                            color: AppColors.primary
                                                .withOpacity(0.1)))
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    child: Text("Deslize para ver o gráfico",
                        style:
                            TextStyle(color: Colors.white24, fontSize: 10))),
              ],
            ),

            // ── Tab Percurso — ALTERAÇÃO 3 ───────────────────────────────
            Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white10)),
                    clipBehavior: Clip.antiAlias,
                    child: activity.route.isEmpty
                        ? const Center(
                            child: Text("Sem percurso GPS gravado",
                                style: TextStyle(color: Colors.white38)))
                        : FlutterMap(
                            options: MapOptions(
                              initialCenter: activity.route.first,
                              initialZoom: 15.0,
                              initialCameraFit: routeBounds != null
                                  ? CameraFit.bounds(
                                      bounds: routeBounds,
                                      padding: const EdgeInsets.all(50))
                                  : null,
                              // Interação ativada para permitir zoom/pan no histórico
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.pinchZoom |
                                    InteractiveFlag.drag,
                              ),
                            ),
                            children: [
                              // ── TILE LAYER (mapa real) adicionado ──
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'com.mobile.heartbox',
                              ),
                              PolylineLayer(polylines: [
                                Polyline(
                                    points: activity.route,
                                    color: AppColors.danger,
                                    strokeWidth: 6,
                                    isDotted: false)
                              ]),
                              MarkerLayer(markers: [
                                Marker(
                                    point: activity.route.first,
                                    width: 14,
                                    height: 14,
                                    child: Container(
                                        decoration: const BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                            border: Border.fromBorderSide(
                                                BorderSide(
                                                    color: Colors.white,
                                                    width: 2))))),
                                Marker(
                                    point: activity.route.last,
                                    width: 14,
                                    height: 14,
                                    child: Container(
                                        decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                            border: Border.fromBorderSide(
                                                BorderSide(
                                                    color: Colors.white,
                                                    width: 2))))),
                              ]),
                            ],
                          ),
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _summaryBox("TEMPO", _formatTime(activity.duration),
                              Icons.timer_outlined),
                          _summaryBox(
                              "DISTÂNCIA",
                              "${activity.distance.toStringAsFixed(0)}m",
                              Icons.directions_walk),
                          _summaryBox("MÉDIA",
                              "${activity.avg.toStringAsFixed(1)}°C", Icons.analytics_outlined)
                        ])),
                const SizedBox(height: 20),
              ],
            ),

            // ── Tab BPM ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(24),
              child: validBpms.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_border,
                              color: Colors.white24, size: 60),
                          SizedBox(height: 16),
                          Text("Sem dados de BPM gravados",
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 16)),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        _bpmStatCard(
                            label: "BPM MÁXIMO",
                            value: "$bpmMax bpm",
                            icon: Icons.arrow_upward_rounded,
                            color: AppColors.danger),
                        const SizedBox(height: 20),
                        _bpmStatCard(
                            label: "BPM MÍNIMO",
                            value: "$bpmMin bpm",
                            icon: Icons.arrow_downward_rounded,
                            color: AppColors.primary),
                        const SizedBox(height: 20),
                        _bpmStatCard(
                            label: "MÉDIA DOS BPMS",
                            value: "${bpmAvg.toStringAsFixed(1)} bpm",
                            icon: Icons.show_chart_rounded,
                            color: AppColors.secondary),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bpmStatCard(
      {required String label,
      required String value,
      required IconData icon,
      required Color color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 32,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detBox(String l, String v) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 10, color: Colors.white38)),
        Text(v,
            style:
                const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))
      ]);

  Widget _summaryBox(String l, String v, IconData i) => Column(children: [
        Icon(i, color: AppColors.primary, size: 20),
        const SizedBox(height: 8),
        Text(l,
            style: const TextStyle(
                fontSize: 10,
                color: Colors.white38,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
      ]);

  String _formatTime(int s) =>
      "${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}";
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo de dados
// ─────────────────────────────────────────────────────────────────────────────
class ActivityData {
  final String? id;
  final String type;
  final int duration;
  final List<double> temperatures;
  final double min, avg, max;
  final List<LatLng> route;
  final double distance;
  final List<int> bpmReadings;
  ActivityData(
      {this.id,
      required this.type,
      required this.duration,
      required this.temperatures,
      required this.min,
      required this.avg,
      required this.max,
      this.route = const [],
      this.distance = 0.0,
      this.bpmReadings = const []});
}

// ─────────────────────────────────────────────────────────────────────────────
// QR Scanner
// ─────────────────────────────────────────────────────────────────────────────
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool isScanning = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Ler QR Code da Placa"),
          backgroundColor: Colors.transparent),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (!isScanning) return;
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  setState(() => isScanning = false);
                  String qrContent = barcode.rawValue!;
                  Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              WifiConfigScreen(targetName: qrContent)));
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 4),
                  borderRadius: BorderRadius.circular(20)),
            ),
          ),
          const Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Text("Aponte para o QR Code da caixa",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuração Wi-Fi via BLE
// ─────────────────────────────────────────────────────────────────────────────
class WifiConfigScreen extends StatefulWidget {
  final String targetName;
  const WifiConfigScreen({super.key, required this.targetName});
  @override
  State<WifiConfigScreen> createState() => _WifiConfigScreenState();
}

class _WifiConfigScreenState extends State<WifiConfigScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool isSending = false;
  bool _obscurePassword = true;
  String statusMessage = "Preencha os dados e clique em Enviar";

  final String UUID_SSID = "ab35e54e-fde4-4f83-902a-07785de547b9";
  final String UUID_PASS = "c1c4b63b-bf3b-4e35-9077-d5426226c710";
  final String UUID_SERVERIP = "0c954d7e-9249-456d-b949-cc079205d393";
  final String SERVICE_UUID_S3 = "0a3b6985-dad6-4759-8852-dcb266d3a59e";
  final String SERVICE_UUID_CAM = "f4b82d49-43c2-48df-b3f5-7ba9e0231908";
  final String SERVICE_UUID_ZERO = "7e408544-2ab3-4581-b541-1188318e8df5";

  Future<void> _enviarDadosBLE() async {
    await SessionManager.setServerIp("20.220.169.18");
    setState(() {
      isSending = true;
      statusMessage = "A procurar as placas (${widget.targetName})...";
    });

    try {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 45));

      int configuredCount = 0;
      Set<String> configuredMacs = {};
      bool isConnecting = false;

      var subscription =
          FlutterBluePlus.scanResults.listen((results) async {
        if (isConnecting) return;

        for (ScanResult r in results) {
          String devName = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : (r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : "");

          bool isOurBoard = devName.contains(widget.targetName.trim()) ||
              devName.contains("Heart_Box");

          for (var uuid in r.advertisementData.serviceUuids) {
            if (uuid.str.toLowerCase() == SERVICE_UUID_S3 ||
                uuid.str.toLowerCase() == SERVICE_UUID_CAM ||
                uuid.str.toLowerCase() == SERVICE_UUID_ZERO) {
              isOurBoard = true;
            }
          }

          if (isOurBoard) {
            String mac = r.device.remoteId.str;
            if (configuredMacs.contains(mac)) continue;

            isConnecting = true;
            configuredMacs.add(mac);
            setState(
                () => statusMessage = "Placa encontrada. A configurar ($mac)...");

            try {
              await r.device
                  .connect(timeout: const Duration(seconds: 10));
              List<BluetoothService> services =
                  await r.device.discoverServices();

              for (var service in services) {
                if (service.uuid.str.toLowerCase() == SERVICE_UUID_S3 ||
                    service.uuid.str.toLowerCase() == SERVICE_UUID_CAM ||
                    service.uuid.str.toLowerCase() == SERVICE_UUID_ZERO) {
                  for (var c in service.characteristics) {
                    if (c.uuid.str.toLowerCase() == UUID_SSID) {
                      await c.write(utf8.encode(_ssidController.text));
                      await Future.delayed(
                          const Duration(milliseconds: 300));
                    }
                    if (c.uuid.str.toLowerCase() == UUID_PASS) {
                      await c.write(utf8.encode(_passController.text));
                      await Future.delayed(
                          const Duration(milliseconds: 300));
                    }
                    if (c.uuid.str.toLowerCase() == UUID_SERVERIP) {
                      String ipEnvio = "20.220.169.18";
                      if (!ipEnvio.contains(':')) ipEnvio += ":8080";
                      await c.write(utf8.encode(ipEnvio));
                      await Future.delayed(
                          const Duration(milliseconds: 500));
                    }
                  }
                }
              }

              await r.device.disconnect();
              configuredCount++;
              if (mounted) {
                setState(() =>
                    statusMessage = "✅ Configurado: $configuredCount/3 placas");
              }

              if (configuredCount >= 3) {
                FlutterBluePlus.stopScan();
                if (mounted) {
                  setState(() {
                    statusMessage =
                        "✅ Sucesso! As três placas foram configuradas.";
                    isSending = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Todas as três placas configuradas!"),
                      backgroundColor: AppColors.success));
                  Future.delayed(const Duration(seconds: 2),
                      () => Navigator.pop(context));
                }
              }
            } catch (e) {
              configuredMacs.remove(mac);
            }

            isConnecting = false;
            break;
          }
        }
      });

      await Future.delayed(const Duration(seconds: 45));

      if (configuredCount < 3) {
        FlutterBluePlus.stopScan();
        if (mounted) {
          setState(() {
            isSending = false;
            if (configuredCount == 0) {
              statusMessage =
                  "❌ Placas não encontradas.\n(Se já estiverem no Wi-Fi, pode fechar este ecrã)";
            } else {
              statusMessage =
                  "⚠️ Apenas $configuredCount/3 placas foram configuradas.";
            }
          });
        }
      }
      subscription.cancel();
    } catch (e) {
      if (mounted) {
        setState(() {
          isSending = false;
          statusMessage = "❌ Falha na comunicação Bluetooth.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Configurar Wi-Fi"),
          backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Alvo: ${widget.targetName}",
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                  labelText: "Nome da Rede Wi-Fi (SSID)",
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15))),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                  labelText: "Password do Wi-Fi",
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15)),
                  suffixIcon: IconButton(
                      icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white60),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword))),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: isSending ? null : _enviarDadosBLE,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15))),
                child: isSending
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text("ENVIAR PARA AS PLACAS",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 30),
            Center(
                child: Text(statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: statusMessage.contains("❌")
                            ? AppColors.danger
                            : Colors.white70))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Câmara térmica (CustomPainter)
// ─────────────────────────────────────────────────────────────────────────────
class ThermalPainter extends CustomPainter {
  final List<int> rawBytes;
  ThermalPainter(this.rawBytes);

  @override
  void paint(Canvas canvas, Size size) {
    final byteData = ByteData.sublistView(Uint8List.fromList(rawBytes));
    List<double> temps = List.filled(768, 0);
    double minT = 1000, maxT = -1000;
    for (int i = 0; i < 768; i++) {
      double t = byteData.getFloat32(i * 4, Endian.little);
      temps[i] = t;
    }
    double sum = 0;
    int count = 0;
    for (double t in temps) {
      if (t >= 15 && t <= 60) {
        if (t < minT) minT = t;
        if (t > maxT) maxT = t;
        sum += t;
        count++;
      }
    }
    double avg = count > 0 ? sum / count : 25.0;
    double cellW = size.width / 32;
    double cellH = size.height / 24;
    for (int y = 0; y < 24; y++) {
      for (int x = 0; x < 32; x++) {
        double t = temps[y * 32 + x];
        if (t < 15 || t > 60) t = avg;
        double normalized =
            maxT > minT ? (t - minT) / (maxT - minT) : 0;
        if (normalized < 0) normalized = 0;
        if (normalized > 1) normalized = 1;
        Color c = _getColor(normalized);
        canvas.drawRect(
            Rect.fromLTWH(x * cellW, y * cellH, cellW + 1, cellH + 1),
            Paint()..color = c);
      }
    }
  }

  Color _getColor(double v) {
    if (v < 0.25) return Color.lerp(Colors.blue, Colors.cyan, v / 0.25)!;
    if (v < 0.50)
      return Color.lerp(Colors.cyan, Colors.green, (v - 0.25) / 0.25)!;
    if (v < 0.75)
      return Color.lerp(Colors.green, Colors.yellow, (v - 0.50) / 0.25)!;
    return Color.lerp(Colors.yellow, Colors.red, (v - 0.75) / 0.25)!;
  }

  @override
  bool shouldRepaint(ThermalPainter old) => true;
}
