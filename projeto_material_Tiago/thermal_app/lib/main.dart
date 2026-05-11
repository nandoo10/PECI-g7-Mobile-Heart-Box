import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
  static String activityType = "Caminhada";
  static DateTime? startTime; 
  static List<double> temps = [];
  static List<int> bpms = []; 
  static double lastLat = 39.3999;
  static double lastLon = -8.2245;
  static List<LatLng> route = [];
  static double distance = 0.0;
  static String serverIp = ""; 

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    serverIp = prefs.getString('serverIp') ?? "";
    hasActiveSession = prefs.getBool('hasActiveSession') ?? false;
    activityType = prefs.getString('activityType') ?? "Caminhada";
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
      route = decodedRoute.map((e) => LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble())).toList();
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

  static Future<void> saveProgress(List<double> t, List<int> b, double la, double lo, List<LatLng> r, double d) async {
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
    await prefs.setString('route', jsonEncode(route.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList()));
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

////////////////////////////////////////////////////
/// 🎨 DESIGN SYSTEM
////////////////////////////////////////////////////
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
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.dark),
        cardTheme: CardThemeData(color: AppColors.surface.withOpacity(0.7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      ),
      home: SessionManager.hasActiveSession 
          ? MonitorScreen(atividade: SessionManager.activityType, retomando: true) 
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
                color: AppColors.primary.withOpacity(0.1)
              )
            )
          ),
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
                          spreadRadius: 10
                        )
                      ]
                    ), 
                    child: const Icon(Icons.monitor_heart_rounded, size: 100, color: AppColors.primary)
                  ),
                  const SizedBox(height: 50),
                  const Text(
                    'Mobile Heart Box', 
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 48, 
                      fontWeight: FontWeight.w900, 
                      letterSpacing: -1.5
                    )
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity, 
                    height: 65,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushReplacement(
                        context, 
                        MaterialPageRoute(builder: (_) => const ActivityMenuScreen())
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary, 
                        foregroundColor: Colors.black, 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                      ),
                      child: const Text('ACEDER AO SISTEMA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
      final url = Uri.parse('http://${SessionManager.serverIp}:1880/lista-atividades');
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        List<ActivityData> listaFinal = [];

        for (var item in data) {
          try {
            List<double> tempsExtraidas = [];
            var rawTemps = item['temperatures'];
            if (rawTemps is List) {
              tempsExtraidas = rawTemps.map((e) => (e as num).toDouble()).toList();
            } else if (rawTemps is String) {
              try {
                var decoded = jsonDecode(rawTemps);
                if (decoded is List) tempsExtraidas = decoded.map((e) => (e as num).toDouble()).toList();
              } catch (_) {
                tempsExtraidas = rawTemps.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();
              }
            }

            List<LatLng> routeExtraida = [];
            var rawRoute = item['route'];
            if (rawRoute != null) {
              try {
                dynamic decoded = rawRoute;
                if (rawRoute is String) decoded = jsonDecode(rawRoute);
                if (decoded is List) {
                  routeExtraida = decoded.map((e) => LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble())).toList();
                }
              } catch(e) { print("Erro rota: $e"); }
            }

            double distExtraida = 0.0;
            if (item['distance'] != null) {
              distExtraida = double.tryParse(item['distance'].toString()) ?? 0.0;
            }

            List<int> bpmExtraidos = [];
            var rawBpm = item['bpm_history'];
            if (rawBpm is List) {
              bpmExtraidos = rawBpm.map((e) => (e as num).toInt()).toList();
            } else if (rawBpm is String) {
              try {
                var decoded = jsonDecode(rawBpm);
                if (decoded is List) bpmExtraidos = decoded.map((e) => (e as num).toInt()).toList();
              } catch (_) {
                bpmExtraidos = rawBpm.split(',').map((e) => int.tryParse(e) ?? 0).toList();
              }
            }

            listaFinal.add(ActivityData(
              id: item['time'],
              type: item['type'] ?? "Atividade",
              duration: item['duracao_segundos'] ?? 0,
              temperatures: tempsExtraidas,
              route: routeExtraida,
              distance: distExtraida,
              min: double.tryParse(item['temp_minima']?.toString() ?? "0") ?? 0.0,
              avg: double.tryParse(item['temp_media']?.toString() ?? "0") ?? 0.0,
              max: double.tryParse(item['temp_maxima']?.toString() ?? "0") ?? 0.0,
              bpmReadings: bpmExtraidos,
            ));
          } catch (e) { print("Erro ao processar item do histórico: $e"); }
        }

        if (mounted) setState(() => activitiesList = listaFinal);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erro de ligação ao PC")));
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
          TextButton(onPressed: () { SessionManager.clear(); Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityScreen())); }, child: const Text("NOVA", style: TextStyle(color: AppColors.danger))),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => MonitorScreen(atividade: SessionManager.activityType, retomando: true))); }, child: const Text("CONTINUAR")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      // ABA 0: CONFIGURAÇÕES (COM LEITOR QR)
      Center(
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
          },
          icon: const Icon(Icons.qr_code_scanner, size: 30),
          label: const Text("Configurar / Controlar Placa via QR"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
          ),
        ),
      ),
      
      // ABA 1: DASHBOARD
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                if (SessionManager.hasActiveSession) {
                  _mostrarDialogoRetomar();
                } else {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityScreen()));
                }
              },
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 30)]),
                child: const Icon(Icons.play_arrow_rounded, size: 80, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 20),
            const Text("INICIAR MONITORIZAÇÃO", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ],
        ),
      ),
      
      // ABA 2: HISTÓRICO
      RefreshIndicator(
        onRefresh: buscarHistoricoDoPC,
        child: ActivityLogScreen(activities: activitiesList, onRefresh: buscarHistoricoDoPC),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "Configurações" : _currentIndex == 1 ? "Dashboard" : "Histórico"), 
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
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Configurações'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_filled, size: 40), label: 'Monitorização'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Histórico'),
        ],
      ),
    );
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String atividade = 'Caminhada';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil'), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            _profileTile('Caminhada', Icons.directions_walk_rounded),
            const SizedBox(height: 15),
            _profileTile('Bicicleta', Icons.directions_bike_rounded),
            const Spacer(),
            SizedBox(width: double.infinity, height: 65, child: ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MonitorScreen(atividade: atividade))), child: const Text("INICIAR", style: TextStyle(fontWeight: FontWeight.bold)))),
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
        decoration: BoxDecoration(color: sel ? AppColors.primary.withOpacity(0.1) : AppColors.surface, borderRadius: BorderRadius.circular(25), border: Border.all(color: sel ? AppColors.primary : Colors.transparent, width: 2)),
        child: Row(children: [Icon(i, color: sel ? AppColors.primary : Colors.white60, size: 30), const SizedBox(width: 25), Text(t, style: TextStyle(fontSize: 20, fontWeight: sel ? FontWeight.bold : FontWeight.normal)), const Spacer(), if (sel) const Icon(Icons.check_circle_rounded, color: AppColors.primary)]),
      ),
    );
  }
}

class MonitorScreen extends StatefulWidget {
  final String atividade;
  final bool retomando;
  const MonitorScreen({super.key, required this.atividade, this.retomando = false});
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
  Uint8List? imageBytes;
  final MapController _mapController = MapController();

  bool isShowingFallAlert = false;

  String proximityStatus = "CAMINHO_LIVRE";
  bool blinkState = true;
  Timer? blinkTimer;

  List<double> ecgPoints = [];
  int currentBpm = 0;
  bool heartBlinkState = false;
  Timer? heartBlinkTimer;
  static const int ecgMaxPoints = 100;

  @override
  void initState() {
    super.initState();
    if (!widget.retomando) {
      SessionManager.start(widget.atividade);
    } else {
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
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !isPaused) {
        setState(() { seconds = SessionManager.elapsedSeconds; });
        SessionManager.saveProgress(allTemps, allBpms, lat, lon, route, distance);
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
    client?.disconnect();
    super.dispose();
  }

  void _triggerHeartBlink() {
    heartBlinkTimer?.cancel();
    setState(() => heartBlinkState = true);
    heartBlinkTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => heartBlinkState = false);
    });
  }

  Future<void> connectMQTT() async {
    client = MqttServerClient(SessionManager.serverIp, 'flutter_${DateTime.now().millisecondsSinceEpoch}');
    try {
      await client!.connect();
      setState(() => connected = true);
      client!.subscribe('heartbox/sensor/thermal', MqttQos.atMostOnce);
      client!.subscribe('heartbox/cam/image', MqttQos.atMostOnce);
      client!.subscribe('heartbox/gps/coords', MqttQos.atMostOnce);
      client!.subscribe('heartbox/alerts/fall', MqttQos.atMostOnce);
      client!.subscribe('heartbox/sensor/proximity', MqttQos.atMostOnce);
      client!.subscribe('heartbox/heart/ecg', MqttQos.atMostOnce);
      client!.subscribe('heartbox/heart/bpm', MqttQos.atMostOnce);

      client!.updates?.listen((c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String topic = c[0].topic;
        final String payload = String.fromCharCodes(recMess.payload.message);

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
            currentTemp = double.tryParse(payload) ?? currentTemp;
            allTemps.add(currentTemp);
          } else if (topic == 'heartbox/cam/image' && showThermal) {
            imageBytes = base64Decode(payload);
          } else if (topic == 'heartbox/gps/coords') {
            if (payload == "Sem sinal GPS" || payload.contains("não detetado") || payload.isEmpty) {
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
                  lat = newLat; lon = newLon;
                  route.add(newPoint);
                } else if (newLat != lat || newLon != lon) {
                  distance += const Distance().distance(LatLng(lat, lon), newPoint);
                  lat = newLat; lon = newLon;
                  route.add(newPoint);
                }
                if (showMap) _mapController.move(newPoint, _mapController.camera.zoom);
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
            currentBpm = newBpm;
            if (newBpm > 0) {
              allBpms.add(newBpm);
              _triggerHeartBlink();
            }
          }
        });
      });
    } catch (e) { print(e); }
  }

  void _mostrarAlertaQueda() {
    if (isShowingFallAlert) return;
    isShowingFallAlert = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.danger,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 30),
            SizedBox(width: 10),
            Text("QUEDA DETETADA!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "Precisa de ajuda?",
          style: TextStyle(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.2)),
                onPressed: () {
                  isShowingFallAlert = false;
                  Navigator.pop(ctx);
                },
                child: const Text("NÃO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.danger),
                onPressed: () {
                  Navigator.pop(ctx);
                  _mostrarDialogoLigar112();
                },
                child: const Text("SIM", style: TextStyle(fontWeight: FontWeight.bold)),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              isShowingFallAlert = false;
              Navigator.pop(ctx);
              final Uri url = Uri.parse('tel:960254309');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
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
        content: const Text("O progresso atual não será guardado no histórico."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CONTINUAR")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () { SessionManager.clear(); Navigator.pop(ctx, true); }, child: const Text("TERMINAR")),
        ],
      ),
    );
    return abandonar ?? false;
  }

  Future<void> finishActivity() async {
    setState(() => isPaused = true);
    final TextEditingController _nameCtrl = TextEditingController(text: widget.atividade);
    bool? salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Finalizar Sessão"),
        content: TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Nome do percurso")),
        actions: [
          TextButton(onPressed: () { setState(() => isPaused = false); Navigator.pop(ctx, false); }, child: const Text("VOLTAR")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("GUARDAR")),
        ],
      ),
    );
    if (salvar == true) {
      try {
        await http.post(Uri.parse('http://${SessionManager.serverIp}:1880/guardar'), 
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            "type": _nameCtrl.text, 
            "duration": seconds, 
            "temperatures": allTemps,
            "distance": distance,
            "route": route.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
            "bpm_history": allBpms, 
          }),
        );
      } catch (e) { print(e); }
      SessionManager.clear();
      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const ActivityMenuScreen()), (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final bool shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const ActivityMenuScreen()), (route) => false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.atividade),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(icon: Icon(Icons.map_rounded, color: showMap ? AppColors.primary : Colors.white38), onPressed: () => setState(() { showMap = !showMap; if(showMap) showThermal = false; })),
            IconButton(icon: Icon(Icons.camera_alt, color: showThermal ? AppColors.primary : Colors.white38), onPressed: () => setState(() { showThermal = !showThermal; if(showThermal) showMap = false; })),
            Padding(padding: const EdgeInsets.only(right: 15), child: Icon(Icons.circle, color: connected ? AppColors.success : AppColors.danger, size: 12))
          ],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (showMap || showThermal)
                  Container(height: 250, width: double.infinity, margin: const EdgeInsets.only(bottom: 15), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)), clipBehavior: Clip.antiAlias, child: showMap ? _buildMapWidget() : _buildThermalWidget()),

                _buildTempAndBpmCards(),

                const SizedBox(height: 15),
                Row(children: [
                  _buildMiniBox("Tempo", _formatTime(seconds), Icons.timer_outlined), 
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
                    Expanded(child: SizedBox(height: 60, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: isPaused ? AppColors.success : Colors.orangeAccent), onPressed: () { setState(() { isPaused = !isPaused; if (!isPaused) SessionManager.adjustStartTimeForPause(seconds); }); }, icon: Icon(isPaused ? Icons.play_arrow : Icons.pause), label: Text(isPaused ? "RETOMAR" : "PAUSAR")))),
                    const SizedBox(width: 15),
                    Expanded(child: SizedBox(height: 60, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger), onPressed: finishActivity, child: const Text("CONCLUIR", style: TextStyle(fontWeight: FontWeight.bold))))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTempAndBpmCards() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(25)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPaused ? "TEMPERATURA (PAUSADO)" : "TEMPERATURA ATUAL",
                  style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
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
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(25)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "BATIMENTOS",
                  style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.favorite,
                        color: heartBlinkState ? AppColors.danger : AppColors.danger.withOpacity(0.3),
                        size: heartBlinkState ? 28 : 22,
                      ),
                    ),
                    const SizedBox(width: 8),
                    currentBpm == 0
                        ? const Text(
                            "Sem\nbatimentos",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white38,
                              height: 1.2,
                            ),
                          )
                        : Text(
                            "$currentBpm bpm",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: isPaused ? Colors.white24 : AppColors.danger,
                            ),
                          ),
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
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(25)),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.monitor_heart_outlined, color: Colors.white24, size: 40),
              SizedBox(height: 8),
              Text("A aguardar sinal ECG...", style: TextStyle(color: Colors.white24)),
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
            child: Text(
              "ECG  ──────────────────────",
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
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
                  getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFF1A2A1A), strokeWidth: 1),
                  getDrawingVerticalLine: (_) => const FlLine(color: Color(0xFF1A2A1A), strokeWidth: 1),
                ),
                titlesData: const FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                      color: AppColors.danger.withOpacity(0.05),
                    ),
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
          child: Text(
            "Não é possível encontrar a sua localização!",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      );
    }
    return FlutterMap(
      mapController: _mapController, 
      options: MapOptions(initialCenter: LatLng(lat, lon), initialZoom: 15), 
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.mobile.heartbox'), 
        PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 4, color: AppColors.danger)]), 
        MarkerLayer(markers: [Marker(point: LatLng(lat, lon), width: 50, height: 50, child: const Icon(Icons.location_on, color: AppColors.danger, size: 40))])
      ]
    );
  }

  Widget _buildProximityBox() {
    bool isDanger = proximityStatus == "OBSTACULO_PERTO";
    Color iconColor = isDanger ? (blinkState ? AppColors.danger : Colors.black) : AppColors.success;
    String label = isDanger ? "Perigo!" : "Livre!";

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(25)),
        child: Row(
          children: [
            Icon(Icons.directions_car_filled, color: iconColor, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Caminho", style: TextStyle(color: Colors.white38, fontSize: 11)),
                Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: iconColor))
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildThermalWidget() => imageBytes != null ? Image.memory(imageBytes!, fit: BoxFit.contain, gaplessPlayback: true) : const Center(child: Text("A aguardar vídeo..."));
  Widget _buildMiniBox(String l, String v, IconData i) => Expanded(child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(25)), child: Row(children: [Icon(i, color: AppColors.primary, size: 20), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(color: Colors.white38, fontSize: 11)), Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))])])));
  Widget _buildGPSStatusBox() => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)), child: Row(children: [const Icon(Icons.gps_fixed, color: AppColors.success, size: 18), const SizedBox(width: 15), Text("GPS | Dist: ${distance.toStringAsFixed(0)}m", style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold))]));
  String _formatTime(int s) => "${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}";
}

class ActivityLogScreen extends StatefulWidget {
  final List<ActivityData> activities;
  final VoidCallback onRefresh;
  const ActivityLogScreen({super.key, required this.activities, required this.onRefresh});
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  Set<String> selectedIds = {};
  bool isSelectionMode = false;

  Future<void> apagarUnica(String id) async {
    bool? confirmar = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(backgroundColor: AppColors.surface, title: const Text("Apagar Atividade?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR")), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("APAGAR", style: TextStyle(color: AppColors.danger)))]));
    if (confirmar == true) { try { await http.delete(Uri.parse('http://${SessionManager.serverIp}:1880/apagar'), headers: {"Content-Type": "application/json"}, body: json.encode({"time": id})); widget.onRefresh(); } catch (e) {} }
  }
  Future<void> apagarMultiplas() async {
    bool? confirmar = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(backgroundColor: AppColors.surface, title: Text("Apagar ${selectedIds.length} atividades?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR")), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("APAGAR TUDO"))]));
    if (confirmar == true) { for (var id in selectedIds) { try { await http.delete(Uri.parse('http://${SessionManager.serverIp}:1880/apagar'), headers: {"Content-Type": "application/json"}, body: json.encode({"time": id})); } catch (e) {} } widget.onRefresh(); setState(() { selectedIds.clear(); isSelectionMode = false; }); }
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
            color: isSelected ? AppColors.primary.withOpacity(0.2) : AppColors.surface, margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: isSelectionMode ? Checkbox(value: isSelected, onChanged: (_) => setState(() => isSelected ? selectedIds.remove(act.id) : selectedIds.add(act.id!))) : const Icon(Icons.history),
              title: Text(act.type, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Dist: ${act.distance.toStringAsFixed(0)}m | Média: ${act.avg.toStringAsFixed(1)}°C"),
              trailing: !isSelectionMode ? IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.danger), onPressed: () => apagarUnica(act.id!)) : null,
              onLongPress: () => setState(() { isSelectionMode = true; selectedIds.add(act.id!); }),
              onTap: () => isSelectionMode ? setState(() => isSelected ? selectedIds.remove(act.id) : selectedIds.add(act.id!)) : Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activity: act))),
            ),
          );
        },
      ),
    );
  }
}

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
    if (dynamicWidth < MediaQuery.of(context).size.width) dynamicWidth = MediaQuery.of(context).size.width;

    LatLngBounds? routeBounds;
    if (activity.route.length >= 2) routeBounds = LatLngBounds.fromPoints(activity.route);

    // Cálculos BPM
    final List<int> validBpms = activity.bpmReadings.where((b) => b > 0).toList();
    final int bpmMin = validBpms.isNotEmpty ? validBpms.reduce((a, b) => a < b ? a : b) : 0;
    final int bpmMax = validBpms.isNotEmpty ? validBpms.reduce((a, b) => a > b ? a : b) : 0;
    final double bpmAvg = validBpms.isNotEmpty ? validBpms.reduce((a, b) => a + b) / validBpms.length : 0.0;

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
            // ABA TEMPERATURA
            Column(
              children: [
                Padding(padding: const EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_detBox("MIN", "${activity.min.toStringAsFixed(1)}°"), _detBox("AVG", "${activity.avg.toStringAsFixed(1)}°"), _detBox("MAX", "${activity.max.toStringAsFixed(1)}°")])),
                const Divider(color: Colors.white10),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(25)),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        width: dynamicWidth,
                        padding: const EdgeInsets.fromLTRB(10, 40, 30, 20),
                        child: activity.temperatures.isEmpty 
                          ? const Center(child: Text("Gráfico não disponível"))
                          : LineChart(
                            LineChartData(
                              minX: 0, maxX: activity.temperatures.length > 1 ? activity.temperatures.length.toDouble() - 1 : 1,
                              minY: (activity.min - 3).clamp(0, 100), maxY: (activity.max + 3).clamp(0, 100),
                              gridData: FlGridData(show: true, drawVerticalLine: true, getDrawingHorizontalLine: (v) => const FlLine(color: Colors.white10, strokeWidth: 1), getDrawingVerticalLine: (v) => const FlLine(color: Colors.white10, strokeWidth: 1)),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 45, getTitlesWidget: (v, m) => Text("${v.toInt()}°", style: const TextStyle(fontSize: 10, color: Colors.white38)))),
                                bottomTitles: AxisTitles(sideTitles: SideTitles(
                                  showTitles: true, reservedSize: 30, interval: intervalX, 
                                  getTitlesWidget: (v, m) {
                                    int s = v.toInt();
                                    if (s == 0) return const Text("0s", style: TextStyle(fontSize: 10, color: Colors.white38));
                                    if (s < 60) return Text("${s}s", style: const TextStyle(fontSize: 10, color: Colors.white38));
                                    if (s < 3600) return Text("${s ~/ 60}m", style: const TextStyle(fontSize: 10, color: Colors.white38));
                                    return Text("${s ~/ 3600}h", style: const TextStyle(fontSize: 10, color: Colors.white38));
                                  }
                                )),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [LineChartBarData(spots: activity.temperatures.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(), isCurved: true, color: AppColors.primary, barWidth: 5, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: AppColors.primary.withOpacity(0.1)))]
                            ),
                          ),
                      ),
                    ),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Text("Deslize para ver o gráfico", style: TextStyle(color: Colors.white24, fontSize: 10))),
              ],
            ),
            // ABA PERCURSO
            Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)),
                    clipBehavior: Clip.antiAlias,
                    child: activity.route.isEmpty 
                      ? const Center(child: Text("Sem percurso GPS gravado", style: TextStyle(color: Colors.white38)))
                      : FlutterMap(
                          options: MapOptions(initialCenter: activity.route.first, initialZoom: 15.0, initialCameraFit: routeBounds != null ? CameraFit.bounds(bounds: routeBounds, padding: const EdgeInsets.all(50)) : null, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
                          children: [
                            PolylineLayer(polylines: [Polyline(points: activity.route, color: AppColors.danger, strokeWidth: 6, isDotted: false)]),
                            MarkerLayer(markers: [
                              Marker(point: activity.route.first, width: 14, height: 14, child: Container(decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2))))),
                              Marker(point: activity.route.last, width: 14, height: 14, child: Container(decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2))))),
                            ]),
                          ],
                        ),
                  ),
                ),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_summaryBox("TEMPO", _formatTime(activity.duration), Icons.timer_outlined), _summaryBox("DISTÂNCIA", "${activity.distance.toStringAsFixed(0)}m", Icons.directions_walk), _summaryBox("MÉDIA", "${activity.avg.toStringAsFixed(1)}°C", Icons.analytics_outlined)])),
                const SizedBox(height: 20),
              ],
            ),
            // ABA BPM
            Padding(
              padding: const EdgeInsets.all(24),
              child: validBpms.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_border, color: Colors.white24, size: 60),
                          SizedBox(height: 16),
                          Text(
                            "Sem dados de BPM gravados",
                            style: TextStyle(color: Colors.white38, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        _bpmStatCard(
                          label: "BPM MÍNIMO",
                          value: "$bpmMin bpm",
                          icon: Icons.arrow_downward_rounded,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 20),
                        _bpmStatCard(
                          label: "BPM MÉDIO",
                          value: "${bpmAvg.toStringAsFixed(1)} bpm",
                          icon: Icons.show_chart_rounded,
                          color: AppColors.secondary,
                        ),
                        const SizedBox(height: 20),
                        _bpmStatCard(
                          label: "BPM MÁXIMO",
                          value: "$bpmMax bpm",
                          icon: Icons.arrow_upward_rounded,
                          color: AppColors.danger,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bpmStatCard({required String label, required String value, required IconData icon, required Color color}) {
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
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detBox(String l, String v) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white38)), Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]);
  Widget _summaryBox(String l, String v, IconData i) => Column(children: [Icon(i, color: AppColors.primary, size: 20), const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]);
  String _formatTime(int s) => "${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}";
}

class ActivityData {
  final String? id; final String type; final int duration; final List<double> temperatures; final double min, avg, max; 
  final List<LatLng> route; final double distance;
  final List<int> bpmReadings;
  ActivityData({this.id, required this.type, required this.duration, required this.temperatures, required this.min, required this.avg, required this.max, this.route = const [], this.distance = 0.0, this.bpmReadings = const []});
}

////////////////////////////////////////////////////
/// 📷 ECRÃ DO LEITOR DE QR CODE (FASE 2)
////////////////////////////////////////////////////
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
        backgroundColor: Colors.transparent,
      ),
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
                  print("QR Lido: $qrContent");

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => WifiConfigScreen(targetName: qrContent)),
                  );
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
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Text(
              "Aponte para o QR Code da caixa",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
    );
  }
}

////////////////////////////////////////////////////
/// 📶 ECRÃ DE CONFIGURAÇÃO WI-FI E BLE
////////////////////////////////////////////////////

// Representa o resultado de tentativa de configuração/comando para uma placa
class _BoardResult {
  final String mac;
  final String name;
  final bool success;
  final String? errorMsg;
  _BoardResult({required this.mac, required this.name, required this.success, this.errorMsg});
}

class WifiConfigScreen extends StatefulWidget {
  final String targetName;
  const WifiConfigScreen({super.key, required this.targetName});

  @override
  State<WifiConfigScreen> createState() => _WifiConfigScreenState();
}

class _WifiConfigScreenState extends State<WifiConfigScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  late final TextEditingController _ipController;
  
  bool isSending = false;
  bool _obscurePassword = true;

  // Estado de progresso visível ao utilizador
  String _statusTitle = "";
  String _statusDetail = "";
  bool _isError = false;

  final String SERVICE_UUID = "0a3b6985-dad6-4759-8852-dcb266d3a59e";
  final String UUID_SSID    = "ab35e54e-fde4-4f83-902a-07785de547b9";
  final String UUID_PASS    = "c1c4b63b-bf3b-4e35-9077-d5426226c710";
  final String UUID_SERVERIP = "0c954d7e-9249-456d-b949-cc079205d393";

  // Nomes BLE conhecidos das placas
  static const List<String> _boardBleNames = ["THERMAL_CAM"];

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: SessionManager.serverIp);
  }

  void _setStatus(String title, String detail, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _statusTitle = title;
      _statusDetail = detail;
      _isError = error;
    });
  }

  /// Verifica se o nome do dispositivo BLE corresponde a uma das nossas placas
  bool _isBoardDevice(String devName) {
    for (final knownName in _boardBleNames) {
      if (devName.contains(knownName) || devName.contains(widget.targetName)) return true;
    }
    return false;
  }

  // ── ALTERAÇÃO 1: _operateOnBoard com 2 tentativas automáticas ─────────────
  /// Executa uma operação numa placa já conectada.
  /// Retorna null se OK, ou mensagem de erro se falhou após 2 tentativas.
  Future<String?> _operateOnBoard(
    BluetoothDevice device,
    Future<void> Function(List<BluetoothService> services) operation,
  ) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        debugPrint('[BLE] Tentativa $attempt para ${device.remoteId.str}');
        await device.connect(timeout: const Duration(seconds: 8));
        final services = await device.discoverServices();
        await operation(services);
        await device.disconnect();
        return null; // sucesso
      } catch (e) {
        try { await device.disconnect(); } catch (_) {}
        debugPrint('[BLE] Tentativa $attempt falhou: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 2));
        } else {
          return e.toString();
        }
      }
    }
    return 'Erro desconhecido';
  }

  /// Encontra características dentro de um serviço pelo UUID
  BluetoothCharacteristic? _findChar(List<BluetoothService> services, String serviceUuid, String charUuid) {
    for (final svc in services) {
      if (svc.uuid.str.toLowerCase() == serviceUuid.toLowerCase()) {
        for (final c in svc.characteristics) {
          if (c.uuid.str.toLowerCase() == charUuid.toLowerCase()) return c;
        }
      }
    }
    return null;
  }

  // ── ALTERAÇÃO 2: scan alargado para 20s + logs de debug ───────────────────
  /// Scan BLE por [scanSeconds] e retorna todos os dispositivos que correspondem às placas.
  Future<List<ScanResult>> _scanForBoards(int scanSeconds) async {
    final found = <String, ScanResult>{};

    StreamSubscription? sub;
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.advName.isNotEmpty
            ? r.device.advName
            : r.advertisementData.advName;
        if (_isBoardDevice(name) && !found.containsKey(r.device.remoteId.str)) {
          found[r.device.remoteId.str] = r;
          debugPrint('[SCAN] Placa encontrada: $name | MAC: ${r.device.remoteId.str}');
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: Duration(seconds: scanSeconds));
    await Future.delayed(Duration(seconds: scanSeconds));
    await FlutterBluePlus.stopScan();
    sub.cancel();

    debugPrint('[SCAN] Total de placas únicas encontradas: ${found.length}');
    for (final e in found.entries) {
      debugPrint('  -> MAC: ${e.key} | Nome: ${e.value.device.advName}');
    }

    return found.values.toList();
  }

  // ── ALTERAÇÃO 3: _enviarDadosBLE com contagem, feedback e delay entre placas
  Future<void> _enviarDadosBLE() async {
    await SessionManager.setServerIp(_ipController.text);

    setState(() { isSending = true; _isError = false; });
    _setStatus("A procurar placas...", "A fazer scan Bluetooth (20s)");

    final boards = await _scanForBoards(20);

    if (boards.isEmpty) {
      _setStatus(
        "✅ Placas já ligadas à rede",
        "Nenhuma placa encontrada em modo Bluetooth.\nAs placas já estão ligadas ao access point configurado.",
      );
      setState(() => isSending = false);
      return;
    }

    _setStatus(
      "A configurar placas...",
      "${boards.length} placa(s) encontrada(s). A iniciar configuração...",
    );

    // Pequeno delay para o utilizador ver a contagem antes de começar
    await Future.delayed(const Duration(seconds: 1));

    final results = <_BoardResult>[];
    for (int i = 0; i < boards.length; i++) {
      final board = boards[i];
      final name = board.device.advName.isNotEmpty
          ? board.device.advName
          : board.advertisementData.advName;

      _setStatus(
        "A configurar placa ${i + 1}/${boards.length}...",
        "Nome: ${name.isNotEmpty ? name : 'Desconhecido'}\nMAC: ${board.device.remoteId.str}",
      );

      final err = await _operateOnBoard(board.device, (services) async {
        final ssidChar  = _findChar(services, SERVICE_UUID, UUID_SSID);
        final passChar  = _findChar(services, SERVICE_UUID, UUID_PASS);
        final ipChar    = _findChar(services, SERVICE_UUID, UUID_SERVERIP);

        if (ssidChar == null || passChar == null || ipChar == null) {
          throw Exception("Características BLE não encontradas");
        }

        await ssidChar.write(utf8.encode(_ssidController.text));
        await passChar.write(utf8.encode(_passController.text));

        String ipEnvio = _ipController.text;
        if (!ipEnvio.contains(':')) ipEnvio += ":8080";
        await ipChar.write(utf8.encode(ipEnvio));
      });

      results.add(_BoardResult(
        mac: board.device.remoteId.str,
        name: name.isNotEmpty ? name : "Placa",
        success: err == null,
        errorMsg: err,
      ));

      // Delay entre placas: dá tempo à placa configurada para iniciar o
      // restart sem interferir com a ligação à placa seguinte
      if (i < boards.length - 1) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    final succeeded = results.where((r) => r.success).toList();
    final failed    = results.where((r) => !r.success).toList();

    String title;
    String detail;
    bool isErr = false;

    if (succeeded.isEmpty) {
      title = "❌ Falha na configuração";
      detail = "Nenhuma placa foi configurada com sucesso.\n"
          + failed.map((r) => "• ${r.name} (${r.mac}): ${r.errorMsg}").join("\n");
      isErr = true;
    } else if (failed.isEmpty) {
      title = succeeded.length == 1
          ? "✅ 1 placa configurada com sucesso"
          : "✅ ${succeeded.length} placas configuradas com sucesso";
      detail = succeeded.map((r) => "• ${r.name} (${r.mac})").join("\n");
    } else {
      title = "⚠️ Configuração parcial";
      detail = "Sucesso (${succeeded.length}):\n"
          + succeeded.map((r) => "• ${r.name} (${r.mac})").join("\n")
          + "\n\nFalha (${failed.length}):\n"
          + failed.map((r) => "• ${r.name} (${r.mac}): ${r.errorMsg}").join("\n");
      isErr = true;
    }

    _setStatus(title, detail, error: isErr);
    setState(() => isSending = false);
  }

  // ── ALTERAÇÃO 4: _enviarComandoBLE com as mesmas melhorias ─────────────────
  Future<void> _enviarComandoBLE(String comando) async {
    setState(() { isSending = true; _isError = false; });

    final String labelComando = comando == "RESET" ? "DESLIGAR" : "LIGAR";
    _setStatus("A procurar placas...", "A fazer scan Bluetooth (20s) para comando $labelComando");

    final boards = await _scanForBoards(20);

    if (boards.isEmpty) {
      if (comando == "RESET") {
        _setStatus(
          "⚠️ Placas não encontradas via Bluetooth",
          "As placas parecem estar ligadas ao Wi-Fi e não estão acessíveis via Bluetooth.\n"
          "Para as desligar, retire a alimentação ou ligue-se diretamente.",
          error: true,
        );
      } else {
        _setStatus(
          "✅ Placas já estão ligadas",
          "Nenhuma placa encontrada em modo Bluetooth.\nAs placas já estão ativas e ligadas à rede.",
        );
      }
      setState(() => isSending = false);
      return;
    }

    _setStatus(
      "A enviar comando $labelComando...",
      "${boards.length} placa(s) encontrada(s). A enviar...",
    );

    await Future.delayed(const Duration(seconds: 1));

    final results = <_BoardResult>[];
    for (int i = 0; i < boards.length; i++) {
      final board = boards[i];
      final name = board.device.advName.isNotEmpty
          ? board.device.advName
          : board.advertisementData.advName;

      _setStatus(
        "A enviar $labelComando a placa ${i + 1}/${boards.length}...",
        "MAC: ${board.device.remoteId.str}",
      );

      final err = await _operateOnBoard(board.device, (services) async {
        final ssidChar = _findChar(services, SERVICE_UUID, UUID_SSID);
        if (ssidChar == null) throw Exception("Característica SSID não encontrada");
        await ssidChar.write(utf8.encode(comando));
      });

      results.add(_BoardResult(
        mac: board.device.remoteId.str,
        name: name.isNotEmpty ? name : "Placa",
        success: err == null,
        errorMsg: err,
      ));

      if (i < boards.length - 1) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    final succeeded = results.where((r) => r.success).toList();
    final failed    = results.where((r) => !r.success).toList();

    String title;
    String detail;
    bool isErr = false;

    if (succeeded.isEmpty) {
      title = "❌ Falha ao enviar comando";
      detail = "O comando $labelComando não chegou a nenhuma placa.\n"
          + failed.map((r) => "• ${r.name} (${r.mac}): ${r.errorMsg}").join("\n");
      isErr = true;
    } else if (failed.isEmpty) {
      title = succeeded.length == 1
          ? "✅ Comando $labelComando enviado a 1 placa"
          : "✅ Comando $labelComando enviado a ${succeeded.length} placas";
      detail = succeeded.map((r) => "• ${r.name} (${r.mac})").join("\n");
    } else {
      title = "⚠️ Comando parcialmente enviado";
      detail = "Sucesso (${succeeded.length}):\n"
          + succeeded.map((r) => "• ${r.name} (${r.mac})").join("\n")
          + "\n\nFalha (${failed.length}):\n"
          + failed.map((r) => "• ${r.name} (${r.mac}): ${r.errorMsg}").join("\n");
      isErr = true;
    }

    _setStatus(title, detail, error: isErr);
    setState(() => isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configuração & Controlo"), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Alvo Bluetooth: ${widget.targetName}", 
                 style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                labelText: "Nome da Rede Wi-Fi (SSID)", 
                filled: true, 
                fillColor: AppColors.surface, 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))
              ),
            ),
            const SizedBox(height: 15),
            
            TextField(
              controller: _passController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: "Password do Wi-Fi", 
                filled: true, 
                fillColor: AppColors.surface, 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white60,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            
            const SizedBox(height: 15),
            
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: "IP do Computador / Cloud", 
                filled: true, 
                fillColor: AppColors.surface, 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))
              ),
            ),
            
            const SizedBox(height: 25),
            
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: isSending ? null : _enviarDadosBLE,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, 
                  foregroundColor: Colors.black, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
                child: isSending 
                    ? const CircularProgressIndicator(color: Colors.black) 
                    : const Text("ENVIAR CREDENCIAIS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(color: Colors.white10, thickness: 2),
            ),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isSending ? null : () => _enviarComandoBLE("ON"),
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text("LIGAR"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success, 
                      foregroundColor: Colors.white, 
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isSending ? null : () => _enviarComandoBLE("RESET"),
                    icon: const Icon(Icons.power_off),
                    label: const Text("DESLIGAR"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger, 
                      foregroundColor: Colors.white, 
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "* DESLIGAR apaga as credenciais Wi-Fi e coloca as placas a dormir.\n"
              "* LIGAR reinicia as placas para modo de operação normal.\n"
              "* Os botões só funcionam enquanto as placas estiverem em modo Bluetooth.",
              style: TextStyle(color: Colors.white24, fontSize: 11),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            // ── Área de resultado ──────────────────────────────────────────
            if (_statusTitle.isNotEmpty)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _isError
                      ? AppColors.danger.withOpacity(0.12)
                      : AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isError
                        ? AppColors.danger.withOpacity(0.4)
                        : AppColors.success.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: _isError ? AppColors.danger : AppColors.success,
                      ),
                    ),
                    if (_statusDetail.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _statusDetail,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),

            if (isSending) ...[
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 12),
                    Text(
                      _statusDetail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
