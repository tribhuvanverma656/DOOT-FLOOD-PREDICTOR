import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'communication/communication_manager.dart';
import 'communication/ble_transport.dart';
import 'communication/alert_codec.dart';
import 'services/alert_audio_service.dart';
import 'package:doot_flood_alert/services/ble_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://yqanamzuoyvabifhyert.supabase.co',
    publishableKey: 'sb_publishable_PkeFUUVBDh4p8ekyzbqmTg_x9uqHYvT',
  );

  runApp(const DootApp());
}

final supabase = Supabase.instance.client;

class DootApp extends StatelessWidget {
  const DootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DOOT Flood Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: 'Roboto',
      ),
      home: const AuthScreen(),
    );
  }
}

// ============================================================================
// GLOBAL HAZARD & LIVE WEATHER BROADCAST STATE
// ============================================================================
class HazardBroadcastState extends ChangeNotifier {
  static final HazardBroadcastState _instance = HazardBroadcastState._internal();
  factory HazardBroadcastState() => _instance;
  HazardBroadcastState._internal();

  double _temperature = 25.5;
  double _windSpeed = 4.2;
  double _precipitation = 0.0;
  double _floodProbability = 15.0;
  String _zoneName = "Delhi-NCR Sector";
  String _threatStatus = "SAFE ZONE: Normal Monitoring";
  Color _threatColor = Colors.green;
  String _meshNotification = "LoRA/BLE Mesh Live • Standby";
  bool _isCritical = false;

  double get temperature => _temperature;
  double get windSpeed => _windSpeed;
  double get precipitation => _precipitation;
  double get floodProbability => _floodProbability;
  String get zoneName => _zoneName;
  String get threatStatus => _threatStatus;
  Color get threatColor => _threatColor;
  String get meshNotification => _meshNotification;
  bool get isCritical => _isCritical;

  void updateWeather({double? temp, double? wind, double? precip}) {
    if (temp != null) _temperature = temp;
    if (wind != null) _windSpeed = wind;
    if (precip != null) _precipitation = precip;
    notifyListeners();
  }

  void updateRisk({
    required double probability,
    required String zoneName,
    String? customThreat,
  }) {
    _floodProbability = probability;
    _zoneName = zoneName;

    if (probability >= 70.0) {
      _threatStatus = customThreat ?? "HIGH-RISK FLOOD WARNING: Move to High Ground";
      _threatColor = Colors.red;
      _isCritical = true;
    } else if (probability >= 40.0) {
      _threatStatus = customThreat ?? "MODERATE WATCH ZONE: Caution Advised";
      _threatColor = Colors.orange;
      _isCritical = false;
    } else {
      _threatStatus = customThreat ?? "SAFE ZONE: Normal Monitoring";
      _threatColor = Colors.green;
      _isCritical = false;
    }
    notifyListeners();
  }

  void updateMeshNotification(String message) {
    _meshNotification = message;
    notifyListeners();
  }
}

class LiveBroadcastBannerWidget extends StatelessWidget {
  const LiveBroadcastBannerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HazardBroadcastState(),
      builder: (context, _) {
        final state = HazardBroadcastState();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: state.isCritical ? const Color(0xFF7F1D1D) : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: state.isCritical ? Colors.red.withValues(alpha: 0.35) : Colors.black12,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: state.threatColor.withValues(alpha: 0.8),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: state.threatColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.threatStatus.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: state.threatColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${state.floodProbability.toStringAsFixed(1)}% RISK',
                      style: TextStyle(
                        color: state.threatColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.thermostat, color: Colors.amber, size: 13),
                      Text(
                        ' ${state.temperature.toStringAsFixed(1)}°C',
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.air, color: Colors.cyanAccent, size: 13),
                      Text(
                        ' ${state.windSpeed.toStringAsFixed(1)} km/h',
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.water_drop, color: Colors.lightBlueAccent, size: 13),
                      Text(
                        ' ${state.precipitation.toStringAsFixed(1)} mm/h',
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cell_tower, color: Colors.greenAccent, size: 12),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            state.meshNotification,
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// RESILIENT MAP TILE LAYER CONFIGURATION
// ============================================================================
TileLayer buildDootTileLayer() {
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    fallbackUrl: 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.doot.flood_app',
    tileProvider: NetworkTileProvider(),
    maxNativeZoom: 19,
    maxZoom: 20,
    keepBuffer: 3,
    panBuffer: 1,
    tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 200)),
    evictErrorTileStrategy: EvictErrorTileStrategy.none,
    errorTileCallback: (tile, error, stackTrace) {
      debugPrint("OSM Tile Loading Fallback for: ${tile.coordinates}");
    },
    tileBuilder: (context, tileWidget, tile) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFE2E8F0),
        ),
        child: tileWidget,
      );
    },
  );
}

// ============================================================================
// BLE / LORA MESH SERVICE
// ============================================================================
class BleMeshService {
  static final BleMeshService _instance = BleMeshService._internal();
  factory BleMeshService() => _instance;
  BleMeshService._internal() {
    _initCommModule();
  }

  final CommunicationManager _commManager = CommunicationManager();
  final List<Map<String, dynamic>> _meshMessages = [];
  final StreamController<List<Map<String, dynamic>>> _meshStreamController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get onMeshPacketsChanged => _meshStreamController.stream;
  CommunicationManager get communicationManager => _commManager;
  BleTransport get bleTransport => _commManager.bleTransport;
  Type get alertCodec => AlertCodec;

  void _initCommModule() {
    _commManager.startMesh();
    _commManager.onAlertReceived.listen((packet) {
      AlertAudioService.playSiren();
      AlertAudioService.isPlayingNotifier.value = true;

      HazardBroadcastState().updateRisk(
        probability: packet.riskScore,
        zoneName: 'MESH RELAY ALERT: ${packet.eventType}',
        customThreat: packet.riskScore >= 70.0
            ? 'HIGH-RISK FLOOD WARNING: Move to High Ground'
            : 'MODERATE WATCH ZONE: Caution Advised',
      );
      HazardBroadcastState().updateMeshNotification('🚨 RELAY: Siren Triggered (${packet.alertId})');

      final map = {
        'alertId': packet.alertId,
        'phone': packet.senderPhone,
        'latitude': packet.latitude,
        'longitude': packet.longitude,
        'message': packet.message,
        'status': packet.eventType == 'SIREN_TRIGGER' ? 'ACTIVE_SIREN' : 'PENDING',
        'riskScore': packet.riskScore,
        'time': 'Realtime Mesh',
        'timestamp': DateTime.fromMillisecondsSinceEpoch(packet.issuedAt).toLocal().toString().split('.').first,
        'ttl': packet.ttl,
        'hopCount': packet.hopCount,
        'isMesh': true,
      };
      if (!_meshMessages.any((m) => m['alertId'] == map['alertId'])) {
        _meshMessages.insert(0, map);
        _meshStreamController.add(List.unmodifiable(_meshMessages));
      }
    });
  }

  Future<bool> broadcastSOS(
    LatLng pos,
    String userPhone, {
    String userName = 'User',
    String message = 'Emergency SOS Alert Broadcasted via Mesh / App',
    double riskScore = 95.0,
  }) async {
    String resolvedLocationName = "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";
    try {
      final geoUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=16',
      );
      final geoRes = await http.get(geoUrl, headers: {'User-Agent': 'com.doot.flood_app'});
      if (geoRes.statusCode == 200) {
        final geoData = jsonDecode(geoRes.body);
        if (geoData['display_name'] != null) {
          resolvedLocationName = geoData['display_name'];
        }
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }

    final packet = await _commManager.broadcastDistress(
      position: pos,
      phone: userPhone,
      message: message,
      riskScore: riskScore,
    );

    final payload = {
      'alertId': packet.alertId,
      'phone': userPhone,
      'name': userName,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'location_name': resolvedLocationName,
      'message': message,
      'status': 'PENDING',
      'time': 'Just now (Mesh)',
      'timestamp': DateTime.now().toLocal().toString().split('.').first,
      'riskScore': riskScore,
      'isMesh': true,
    };

    if (!_meshMessages.any((m) => m['alertId'] == payload['alertId'])) {
      _meshMessages.insert(0, payload);
      _meshStreamController.add(List.unmodifiable(_meshMessages));
    }

    HazardBroadcastState().updateRisk(
      probability: riskScore,
      zoneName: 'User Distress SOS',
      customThreat: 'HIGH-RISK FLOOD WARNING: Move to High Ground',
    );
    HazardBroadcastState().updateMeshNotification('🚨 Mesh SOS Broadcast: ${packet.alertId}');

    supabase.from('distress_alerts').insert({
      'phone': userPhone,
      'name': userName,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'location_name': resolvedLocationName,
      'message': '$message | Location: $resolvedLocationName',
      'status': 'PENDING',
    }).then((_) {
      debugPrint("Supabase cloud sync finished for ${packet.alertId}");
    }).catchError((e) {
      debugPrint("Supabase Sync Error: $e");
    });

    return true;
  }

  Future<bool> broadcastMeshSiren(
    LatLng pos, {
    double riskScore = 98.0,
    String message = 'CRITICAL FLOOD SIREN: Multi-Device Emergency Alert Triggered',
  }) async {
    final packet = await _commManager.broadcastSirenTrigger(
      position: pos,
      message: message,
      riskScore: riskScore,
    );

    final payload = {
      'alertId': packet.alertId,
      'phone': 'MESH_SIREN_NODE',
      'name': 'System Siren Node',
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'message': message,
      'status': 'ACTIVE_SIREN',
      'time': 'Just now (Mesh)',
      'timestamp': DateTime.now().toLocal().toString().split('.').first,
      'riskScore': riskScore,
      'isMesh': true,
    };

    if (!_meshMessages.any((m) => m['alertId'] == payload['alertId'])) {
      _meshMessages.insert(0, payload);
      _meshStreamController.add(List.unmodifiable(_meshMessages));
    }

    HazardBroadcastState().updateMeshNotification('🚨 Siren Broadcast Active (${packet.alertId})');
    return true;
  }

  List<Map<String, dynamic>> getReceivedPackets() => List.unmodifiable(_meshMessages);

  void removePacketById(String alertId) {
    _meshMessages.removeWhere((m) => m['alertId'] == alertId);
    _meshStreamController.add(List.unmodifiable(_meshMessages));
  }
}

// ============================================================================
// 1. AUTH SCREEN WITH APP LOGO & STRICT 10-DIGIT MOBILE VALIDATION
// ============================================================================
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveUserAndProceed() async {
    final rawPhone = _inputController.text.trim();
    final name = _nameController.text.trim();

    // Remove non-numeric characters to get exact digit count
    final digitsOnly = rawPhone.replaceAll(RegExp(r'\D'), '');

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your full name.')),
      );
      return;
    }

    // Strict 10-digit check validation
    if (digitsOnly.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Mobile Number! Please enter a valid 10-digit phone number.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final formattedPhone = '+91 $digitsOnly';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_phone', formattedPhone);
    await prefs.setString('user_name', name);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainNavigationHolder()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  // DOOT APP OFFICIAL LOGO (Shield + Water drops)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.shade200, width: 2),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(Icons.shield, size: 64, color: Colors.blue.shade700),
                        const Positioned(
                          top: 18,
                          child: Icon(Icons.water_drop, size: 28, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'DOOT FLOOD MONITOR',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'AI-Powered Emergency Response',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.person),
                      hintText: 'Enter Full Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inputController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.phone),
                      prefixText: '+91 ',
                      hintText: 'Enter 10-Digit Mobile',
                      counterText: '',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saveUserAndProceed,
                      child: const Text('Get OTP & Continue', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 2. MAIN BOTTOM NAVIGATION HOLDER
// ============================================================================
class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;

  LatLng _userPos = const LatLng(28.6692, 77.4538);
  LatLng _targetPos = const LatLng(28.6129, 77.2773);
  String _targetName = "Akshardham Relief Camp";

  bool _isSirenPlaying = false;

  @override
  void initState() {
    super.initState();
    _determinePosition();
    AlertAudioService.isPlayingNotifier.addListener(_syncSirenState);
  }

  void _syncSirenState() {
    if (mounted && _isSirenPlaying != AlertAudioService.isPlayingNotifier.value) {
      setState(() => _isSirenPlaying = AlertAudioService.isPlayingNotifier.value);
    }
  }

  @override
  void dispose() {
    AlertAudioService.isPlayingNotifier.removeListener(_syncSirenState);
    super.dispose();
  }

  Future<void> _determinePosition() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return;
      }
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _userPos = LatLng(pos.latitude, pos.longitude);
        });
      }
    } catch (_) {}
  }

  void _updateTargetLocation(LatLng pos, String name) {
    setState(() {
      _targetPos = pos;
      _targetName = name;
    });
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _startSiren() async {
    if (_isSirenPlaying) return;

    try {
      await AlertAudioService.playSiren();
    } catch (e) {
      debugPrint('Local Audio Siren play error: $e');
    }

    try {
      await BleService.sendAlert();
    } catch (e) {
      debugPrint('BLE Send Siren Alert error: $e');
    }

    HazardBroadcastState().updateMeshNotification('🚨 Multi-Device Siren Active');
    if (mounted) setState(() => _isSirenPlaying = true);
  }

  Future<void> _stopSiren() async {
    try {
      await AlertAudioService.stopSiren();
      AlertAudioService.isPlayingNotifier.value = false;
    } catch (e) {
      debugPrint('Local Audio Siren stop error: $e');
    }

    try {
      await BleService.stopAlertSound();
    } catch (e) {
      debugPrint('BLE Stop Siren Alert error: $e');
    }

    HazardBroadcastState().updateMeshNotification('LoRA/BLE Mesh Live • Standby');
    if (mounted) setState(() => _isSirenPlaying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            userPos: _userPos,
            isSirenPlaying: _isSirenPlaying,
            onStartSiren: _startSiren,
            onStopSiren: _stopSiren,
            onRecenter: _determinePosition,
            onLogout: _logout,
          ),
          RiskMapScreen(
            userPos: _userPos,
            onTargetSelected: (pos, name) {
              _updateTargetLocation(pos, name);
              setState(() => _currentIndex = 2);
            },
            onTriggerSiren: _startSiren,
          ),
          NavigationScreen(
            userPos: _userPos,
            targetPos: _targetPos,
            targetName: _targetName,
          ),
          const NDRFCommandScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.blue.shade700,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Risk Map'),
          BottomNavigationBarItem(icon: Icon(Icons.navigation), label: 'Navigation'),
          BottomNavigationBarItem(icon: Icon(Icons.security), label: 'NDRF Command'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: HOME SCREEN
// ============================================================================
class HomeScreen extends StatefulWidget {
  final LatLng userPos;
  final bool isSirenPlaying;
  final VoidCallback onStartSiren;
  final VoidCallback onStopSiren;
  final Future<void> Function() onRecenter;
  final VoidCallback onLogout;

  const HomeScreen({
    super.key,
    required this.userPos,
    required this.isSirenPlaying,
    required this.onStartSiren,
    required this.onStopSiren,
    required this.onRecenter,
    required this.onLogout,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double temp = 25.5;
  double wind = 4.2;
  double precip = 0.0;
  bool isLoadingWeather = true;

  String userName = '';
  String userPhone = '';

  @override
  void initState() {
    super.initState();
    _loadStoredUserData();
    _fetchLiveWeather();
  }

  Future<void> _loadStoredUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        userName = prefs.getString('user_name') ?? 'User';
        userPhone = prefs.getString('user_phone') ?? '';
      });
    }
  }

  Future<void> _fetchLiveWeather() async {
    setState(() => isLoadingWeather = true);
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${widget.userPos.latitude}&longitude=${widget.userPos.longitude}&current=temperature_2m,wind_speed_10m,precipitation,weather_code',
    );
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final current = data['current'] ?? {};
        temp = (current['temperature_2m'] as num?)?.toDouble() ?? 25.5;
        wind = (current['wind_speed_10m'] as num?)?.toDouble() ?? 4.2;
        precip = (current['precipitation'] as num?)?.toDouble() ?? 0.0;
        HazardBroadcastState().updateWeather(temp: temp, wind: wind, precip: precip);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoadingWeather = false);
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Calling $phoneNumber...')),
        );
      }
    }
  }

  // SOS button: sirf NDRF ko distress message bhejta hai (via BleMeshService.broadcastSOS,
  // jo Supabase 'distress_alerts' table me insert karta hai). Yeh BLE siren/warning
  // ko TRIGGER NAHI karta — woh sirf START SIREN button se hota hai.
  Future<void> _sendSOS() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? userPhone;
    final name = prefs.getString('user_name') ?? userName;

    await BleMeshService().broadcastSOS(
      widget.userPos,
      phone,
      userName: name,
      message: 'CRITICAL EMERGENCY: User $name ($phone) requested immediate rescue.',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cell_tower, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'SOS sent to NDRF for $name ($phone)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        titleSpacing: 12,
        title: Row(
          children: [
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'DOOT DASHBOARD',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Color(0xFF0F172A),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade600, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cell_tower, color: Colors.amber.shade800, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'BLE/LoRA Mesh Active',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54, size: 20),
            tooltip: 'Refresh Weather',
            onPressed: _fetchLiveWeather,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54, size: 20),
            tooltip: 'Logout',
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LiveBroadcastBannerWidget(),
            SizedBox(
              height: 200,
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: widget.userPos,
                      initialZoom: 13.5,
                    ),
                    children: [
                      buildDootTileLayer(),
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: widget.userPos,
                            radius: 200,
                            useRadiusInMeter: true,
                            color: Colors.red.withValues(alpha: 0.2),
                            borderColor: Colors.red,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: widget.userPos,
                            child: const Icon(Icons.adjust, color: Colors.blue, size: 32),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.my_location, color: Colors.blue, size: 20),
                        onPressed: () async {
                          await widget.onRecenter();
                          _fetchLiveWeather();
                        },
                      ),
                    ),
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User: $userName ${userPhone.isNotEmpty ? "($userPhone)" : ""}',
                    style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Status: Yamuna Basin High Danger Flood Plain',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'No stored hazard warnings.',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIVE LOCAL WEATHER',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.cloud_queue, color: Colors.blue, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isLoadingWeather
                                    ? 'Loading Weather...'
                                    : '${temp.toStringAsFixed(1)}°C  |  Wind: ${wind.toStringAsFixed(1)} km/h  |  Rain: ${precip.toStringAsFixed(1)} mm/h',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'RISK OVERVIEW',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatCard('High', 'Risk Level', Icons.warning, Colors.red),
                      _buildStatCard('12', 'Affected Areas', Icons.location_city, Colors.orange),
                      _buildStatCard('2.4M', 'At Risk', Icons.groups, Colors.blue),
                      _buildStatCard('86%', 'Mesh Active', Icons.check_circle, Colors.green),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE53935),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _sendSOS,
                      child: const Text(
                        'SOS SEND EMERGENCY SOS ALERT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.isSirenPlaying
                                  ? const Color(0xFFE65100).withValues(alpha: 0.4)
                                  : const Color(0xFFE65100),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.campaign, size: 20),
                            label: const Text(
                              'START SIREN',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
                            ),
                            // Start Siren: BLE ke through warning signal bhejta hai + local siren bajata hai.
                            onPressed: widget.isSirenPlaying ? null : widget.onStartSiren,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.isSirenPlaying
                                  ? Colors.grey.shade900
                                  : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.stop_circle_outlined, size: 20),
                            label: const Text(
                              'STOP SIREN',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
                            ),
                            // Stop Siren: local siren aur BLE alert dono band kar deta hai.
                            onPressed: widget.isSirenPlaying ? widget.onStopSiren : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'DIRECT EMERGENCY HELPLINES',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A8A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.local_police, size: 16),
                          label: const Text('POLICE (112)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => _makePhoneCall('112'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF15803D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.medical_services, size: 16),
                          label: const Text('AMBULANCE (108)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => _makePhoneCall('108'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String val, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(val, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 8, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 2: LIVE RISK MAP & PREDICTOR
// ============================================================================
class RiskMapScreen extends StatefulWidget {
  final LatLng userPos;
  final Function(LatLng, String) onTargetSelected;
  final VoidCallback onTriggerSiren;

  const RiskMapScreen({
    super.key,
    required this.userPos,
    required this.onTargetSelected,
    required this.onTriggerSiren,
  });

  @override
  State<RiskMapScreen> createState() => _RiskMapScreenState();
}

class _RiskMapScreenState extends State<RiskMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _pinnedLocation;
  String _selectedTargetName = "Current View Target";
  double _currentProbability = 85.0;
  String _riskLevelBadge = "HIGH RISK ZONE";
  Color _riskColor = Colors.red;

  String _weatherText = "Temp: --°C | Wind: -- km/h | Rain: -- mm/h";
  double _livePrecipitation = 0.0;
  double _liveWindSpeed = 4.0;
  double _liveTemperature = 25.0;
  bool _isLoadingWeather = false;

  List<Map<String, dynamic>> _csvAlertReaches = [];

  final List<Map<String, dynamic>> _reliefCamps = [
    {'name': 'Akshardham Relief Camp', 'pos': const LatLng(28.6129, 77.2773)},
    {'name': 'Geeta Colony Shelter Ground', 'pos': const LatLng(28.6500, 77.2600)},
    {'name': 'Mayur Vihar Relief Center', 'pos': const LatLng(28.6010, 77.2980)},
  ];

  @override
  void initState() {
    super.initState();
    _loadCSVData();
    _fetchWeatherForLocation(widget.userPos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _loadCSVData() {
    setState(() {
      _csvAlertReaches = [
        {'lat': 29.321405, 'lon': 78.075038, 'level': 'RED_HIGH_ALERT', 'prob': 0.755787},
        {'lat': 30.366541, 'lon': 77.624386, 'level': 'RED_HIGH_ALERT', 'prob': 0.878165},
        {'lat': 30.595053, 'lon': 77.755748, 'level': 'RED_HIGH_ALERT', 'prob': 0.794213},
        {'lat': 28.669200, 'lon': 77.453800, 'level': 'RED_HIGH_ALERT', 'prob': 0.938000},
        {'lat': 28.706325, 'lon': 77.506206, 'level': 'RED_HIGH_ALERT', 'prob': 0.824000},
        {'lat': 28.800000, 'lon': 77.600000, 'level': 'ORANGE_SURGE_WATCH', 'prob': 0.640000},
        {'lat': 28.615000, 'lon': 77.250000, 'level': 'RED_HIGH_ALERT', 'prob': 0.948000},
        {'lat': 28.900000, 'lon': 78.100000, 'level': 'GREEN_MONITORED', 'prob': 0.150000},
        {'lat': 29.133528, 'lon': 78.072125, 'level': 'ORANGE_SURGE_WATCH', 'prob': 0.580000},
      ];
    });
  }

  Future<void> _fetchWeatherForLocation(LatLng targetPos) async {
    setState(() => _isLoadingWeather = true);
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${targetPos.latitude}&longitude=${targetPos.longitude}&current=temperature_2m,wind_speed_10m,precipitation,weather_code',
    );
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final current = data['current'] ?? {};
        _liveTemperature = (current['temperature_2m'] as num?)?.toDouble() ?? 25.0;
        _liveWindSpeed = (current['wind_speed_10m'] as num?)?.toDouble() ?? 4.0;
        _livePrecipitation = (current['precipitation'] as num?)?.toDouble() ?? 0.0;
        _weatherText = "Temp: ${_liveTemperature.toStringAsFixed(1)}°C | Wind: ${_liveWindSpeed.toStringAsFixed(1)} km/h | Rain: ${_livePrecipitation.toStringAsFixed(1)} mm/h";
        HazardBroadcastState().updateWeather(
          temp: _liveTemperature,
          wind: _liveWindSpeed,
          precip: _livePrecipitation,
        );
      } else {
        _weatherText = "Weather Data Unavailable";
      }
    } catch (_) {
      _weatherText = "Weather Data Unavailable";
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  double _calculateDistanceKm(LatLng p1, LatLng p2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((p2.latitude - p1.latitude) * p) / 2 +
        c(p1.latitude * p) * c(p2.latitude * p) * (1 - c((p2.longitude - p1.longitude) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  double _calculateHighPrecisionRisk(LatLng latlng, {double? livePrecip, double? liveWind}) {
    double nearestReachProb = 0.20;
    double minDistanceKm = double.infinity;

    for (var reach in _csvAlertReaches) {
      double dist = _calculateDistanceKm(latlng, LatLng(reach['lat'], reach['lon']));
      if (dist < minDistanceKm) {
        minDistanceKm = dist;
        nearestReachProb = reach['prob'];
      }
    }

    double distanceDecay = exp(-minDistanceKm / 8.5);
    double reachRiskComponent = nearestReachProb * distanceDecay * 60.0;

    double latCenter = 28.62;
    double lonCenter = 77.26;
    double basinDist = sqrt(pow(latlng.latitude - latCenter, 2) + pow(latlng.longitude - lonCenter, 2));
    double elevationProxy = 200.0 + min(40.0, basinDist * 100.0);
    double elevationRiskComponent = max(0.0, (230.0 - elevationProxy) * 0.45);

    double precip = livePrecip ?? _livePrecipitation;
    double wind = liveWind ?? _liveWindSpeed;
    double rainRiskComponent = min(35.0, precip * 1.8 + (precip > 10.0 ? 8.0 : 0.0));
    double windRiskComponent = min(10.0, max(0.0, (wind - 5.0) * 0.4));

    double totalScore = reachRiskComponent + elevationRiskComponent + rainRiskComponent + windRiskComponent;

    if (minDistanceKm < 2.5 && nearestReachProb >= 0.85) {
      totalScore = max(totalScore, nearestReachProb * 100.0);
    }

    return totalScore.clamp(5.0, 99.8);
  }

  void _handleLongPress(TapPosition pos, LatLng latlng) async {
    setState(() {
      _pinnedLocation = latlng;
    });

    await _fetchWeatherForLocation(latlng);
    final risk = _calculateHighPrecisionRisk(latlng);

    _updateTargetPrediction(
      "Pinned: ${latlng.latitude.toStringAsFixed(3)}, ${latlng.longitude.toStringAsFixed(3)}",
      risk,
      location: latlng,
    );
  }

  Future<void> _searchLocation() async {
    String q = _searchController.text.trim();
    if (q.isEmpty) return;

    final url = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(q)}');
    try {
      final res = await http.get(url, headers: {'User-Agent': 'com.doot.flood_app'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        if (data.isNotEmpty) {
          double lat = double.parse(data[0]['lat']);
          double lon = double.parse(data[0]['lon']);
          LatLng target = LatLng(lat, lon);

          _mapController.move(target, 11.5);
          setState(() {
            _pinnedLocation = target;
          });

          await _fetchWeatherForLocation(target);
          double calculatedRisk = _calculateHighPrecisionRisk(target);
          _updateTargetPrediction(q.toUpperCase(), calculatedRisk, location: target);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No results found for "$q".')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search failed. Check your connection.')),
        );
      }
    }
  }

  void _updateTargetPrediction(String name, double probability, {LatLng? location}) {
    setState(() {
      _selectedTargetName = name;
      _currentProbability = probability;

      if (probability >= 70.0) {
        _riskLevelBadge = "HIGH RISK ZONE";
        _riskColor = Colors.red;
      } else if (probability >= 40.0) {
        _riskLevelBadge = "MODERATE WATCH ZONE";
        _riskColor = Colors.orange;
      } else {
        _riskLevelBadge = "SAFE MONITORED ZONE";
        _riskColor = Colors.green;
      }
    });

    HazardBroadcastState().updateRisk(probability: probability, zoneName: name);

    if (probability > 93.0) {
      widget.onTriggerSiren();
      AlertAudioService.playSiren();

      final targetLoc = location ?? _pinnedLocation ?? widget.userPos;
      BleMeshService().broadcastMeshSiren(targetLoc, riskScore: probability);
      BleMeshService().broadcastSOS(
        targetLoc,
        'AUTO-SENSOR-93',
        userName: 'Auto Detector Node',
        message: 'URGENT: Flash flood risk critical at ${probability.toStringAsFixed(1)}% in $name.',
        riskScore: probability,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🚨 CRITICAL FLOOD RISK (${probability.toStringAsFixed(1)}%)! Siren activated.',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.userPos,
                initialZoom: 9.5,
                onLongPress: _handleLongPress,
              ),
              children: [
                buildDootTileLayer(),
                CircleLayer(
                  circles: _csvAlertReaches.map((reach) {
                    Color c = Colors.green;
                    double r = 4000;

                    if (reach['level'] == 'RED_HIGH_ALERT') {
                      c = Colors.red;
                      r = 12000;
                    } else if (reach['level'] == 'ORANGE_SURGE_WATCH') {
                      c = Colors.orange;
                      r = 8000;
                    }

                    return CircleMarker(
                      point: LatLng(reach['lat'], reach['lon']),
                      radius: r,
                      useRadiusInMeter: true,
                      color: c.withValues(alpha: 0.35),
                      borderColor: c,
                      borderStrokeWidth: 2,
                    );
                  }).toList(),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.userPos,
                      child: const Icon(Icons.location_on, color: Colors.blue, size: 38),
                    ),
                    if (_pinnedLocation != null)
                      Marker(
                        point: _pinnedLocation!,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 38),
                      ),
                    ..._reliefCamps.map((camp) {
                      return Marker(
                        point: camp['pos'],
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _pinnedLocation = camp['pos']);
                            _updateTargetPrediction(camp['name'], 12.5, location: camp['pos']);
                            _fetchWeatherForLocation(camp['pos']);
                          },
                          child: const Icon(Icons.night_shelter, color: Colors.orange, size: 30),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 6,
              left: 10,
              right: 10,
              child: Column(
                children: [
                  const LiveBroadcastBannerWidget(),
                  const SizedBox(height: 4),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                hintText: 'Search location to predict flo...',
                                hintStyle: TextStyle(color: Colors.black45, fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onSubmitted: (_) => _searchLocation(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.search, color: Colors.blue, size: 22),
                            onPressed: _searchLocation,
                          ),
                          IconButton(
                            icon: const Icon(Icons.my_location, color: Colors.green, size: 22),
                            onPressed: () {
                              _mapController.move(widget.userPos, 12.0);
                              _updateTargetPrediction("User Live Location", 85.0);
                              _fetchWeatherForLocation(widget.userPos);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Card(
                    color: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: _riskColor, width: 1.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedTargetName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Flood Probability: ${_currentProbability.toStringAsFixed(1)}%',
                                    style: TextStyle(color: _riskColor, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _riskColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _riskLevelBadge,
                                  style: TextStyle(color: _riskColor, fontWeight: FontWeight.bold, fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 14),
                          Row(
                            children: [
                              const Icon(Icons.cloud_queue, size: 16, color: Colors.blue),
                              const SizedBox(width: 6),
                              _isLoadingWeather
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(
                                      _weatherText,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                                    ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              icon: const Icon(Icons.navigation, size: 16),
                              label: const Text(
                                'Navigate Here',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: () {
                                final target = _pinnedLocation ?? widget.userPos;
                                widget.onTargetSelected(target, _selectedTargetName);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _customLegendItem(
                      'Danger Zone',
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      ),
                    ),
                    _customLegendItem(
                      'Safe Corridor',
                      Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.alt_route, size: 10, color: Colors.white),
                      ),
                    ),
                    _customLegendItem(
                      'Relief Camp',
                      const Icon(Icons.night_shelter, size: 16, color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customLegendItem(String title, Widget iconWidget) {
    return Row(
      children: [
        iconWidget,
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}

// ============================================================================
// TAB 3: NAVIGATION SCREEN (WITH LIVE LOCATION PIN & BOTTOM-LEFT STEP GUIDANCE)
// ============================================================================
class NavigationScreen extends StatefulWidget {
  final LatLng userPos;
  final LatLng targetPos;
  final String targetName;

  const NavigationScreen({
    super.key,
    required this.userPos,
    required this.targetPos,
    required this.targetName,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();

  late LatLng _currentLocation;
  late LatLng _destination;
  late String _destinationName;

  List<LatLng> polylinePoints = [];
  List<String> steps = [];
  double distanceKm = 0.0;
  double durationMin = 0.0;
  double _bearing = 0.0;

  bool _isNavigating = false;
  int _currentStepIndex = 0;
  Timer? _simulationTimer;
  bool _isMuted = false;

  bool _showDangerZones = true;
  bool _showSafeCorridors = true;
  bool _showReliefCamps = true;

  final List<Map<String, dynamic>> _shelters = [
    {'name': 'Akshardham Relief Camp', 'pos': const LatLng(28.6129, 77.2773)},
    {'name': 'Mayur Vihar Shelter Ground', 'pos': const LatLng(28.6010, 77.2980)},
    {'name': 'Ghaziabad Community Relief Center', 'pos': const LatLng(28.6690, 77.4380)},
    {'name': 'Noida Stadium Emergency Camp', 'pos': const LatLng(28.5800, 77.3300)},
  ];

  final List<Map<String, dynamic>> _riskZones = [
    {'name': 'Yamuna Bank High Risk Flood Plain', 'pos': const LatLng(28.6150, 77.2500), 'radius': 1200.0},
    {'name': 'Hindon River Danger Zone', 'pos': const LatLng(28.6500, 77.4100), 'radius': 1500.0},
  ];

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.userPos;
    _destination = widget.targetPos;
    _destinationName = widget.targetName;
    _initTts();
    _loadMutePreference();
    _fetchOSRMRoute();
  }

  void _loadMutePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isMuted = prefs.getBool('nav_is_muted') ?? false;
      });
    }
  }

  void _toggleMute() async {
    final newMuted = !_isMuted;
    setState(() {
      _isMuted = newMuted;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('nav_is_muted', newMuted);
    if (newMuted) {
      await _flutterTts.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Voice guidance muted."), duration: Duration(seconds: 1)),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Voice guidance unmuted."), duration: Duration(seconds: 1)),
        );
      }
      _speak("Voice guidance enabled.");
    }
  }

  @override
  void didUpdateWidget(covariant NavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetPos != widget.targetPos) {
      setState(() {
        _destination = widget.targetPos;
        _destinationName = widget.targetName;
      });
      _fetchOSRMRoute();
    }
  }

  void _initTts() async {
    await _flutterTts.setLanguage("en-IN");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    if (_isMuted) {
      await _flutterTts.stop();
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _flutterTts.stop();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitudeInRad;
    double lat2 = end.latitudeInRad;
    double dLng = (end.longitude - start.longitude) * (pi / 180.0);

    double y = sin(dLng) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    double brng = atan2(y, x) * (180.0 / pi);
    return (brng + 360.0) % 360.0;
  }

  // Google Maps Style: Center & Pin Current Live Location
  Future<void> _pinLiveLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      LatLng livePos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentLocation = livePos;
      });
      _mapController.move(livePos, 15.0);
      _fetchOSRMRoute();
      _speak("Live location pinned.");
    } catch (e) {
      debugPrint("Error fetching live location: $e");
    }
  }

  Future<void> _searchAndRoute() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    final url = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}');
    try {
      final res = await http.get(url, headers: {'User-Agent': 'com.doot.flood_app'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        if (data.isNotEmpty) {
          double lat = double.parse(data[0]['lat']);
          double lon = double.parse(data[0]['lon']);
          LatLng target = LatLng(lat, lon);

          setState(() {
            _destination = target;
            _destinationName = query.toUpperCase();
          });

          _mapController.move(target, 12.0);
          _fetchOSRMRoute();
          _speak("Route calculated to $_destinationName");
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No results found for "$query".')),
          );
        }
      }
    } catch (e) {
      debugPrint("Search error: $e");
    }
  }

  Future<void> _fetchOSRMRoute() async {
    final url = Uri.parse(
      'https://routing.openstreetmap.de/routed-car/route/v1/driving/'
      '${_currentLocation.longitude},${_currentLocation.latitude};'
      '${_destination.longitude},${_destination.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final r = data['routes'][0];
          final List coords = r['geometry']['coordinates'];
          List<LatLng> parsedPoints =
              coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();

          List<String> routeSteps = [];
          final legs = r['legs'] as List;
          if (legs.isNotEmpty) {
            for (var s in legs[0]['steps']) {
              String stepInstruction = "${s['maneuver']['type']} ${s['maneuver']['modifier'] ?? ''} on ${s['name']}"
                  .trim()
                  .toUpperCase();
              routeSteps.add(stepInstruction);
            }
          }

          if (mounted) {
            setState(() {
              polylinePoints = parsedPoints;
              distanceKm = (r['distance'] as num).toDouble() / 1000;
              durationMin = (r['duration'] as num).toDouble() / 60;
              steps = routeSteps.isEmpty ? ["DEPART ON SAFE ROUTE"] : routeSteps;
              _bearing = _calculateBearing(_currentLocation, _destination);
              _currentStepIndex = 0;
            });
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          polylinePoints = [_currentLocation, _destination];
        });
      }
    }
  }

  void _onMapLongPress(TapPosition tapPosition, LatLng latlng) {
    setState(() {
      _destination = latlng;
      _destinationName = "Pinned Location (${latlng.latitude.toStringAsFixed(3)}, ${latlng.longitude.toStringAsFixed(3)})";
    });
    _fetchOSRMRoute();
    _speak("Location locked. Routing to selected point.");
  }

  void _startNavigation() {
    if (polylinePoints.isEmpty) return;

    setState(() => _isNavigating = true);
    _speak("Starting navigation to $_destinationName. ${steps.first}");

    int pointIndex = 0;
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || !_isNavigating || pointIndex >= polylinePoints.length - 1) {
        timer.cancel();
        if (pointIndex >= polylinePoints.length - 1) {
          _speak("You have arrived at your destination shelter.");
          if (mounted) setState(() => _isNavigating = false);
        }
        return;
      }

      pointIndex++;
      setState(() {
        _currentLocation = polylinePoints[pointIndex];
        if (pointIndex % 3 == 0 && _currentStepIndex < steps.length - 1) {
          _currentStepIndex++;
          _speak(steps[_currentStepIndex]);
        }
        _bearing = _calculateBearing(_currentLocation, polylinePoints[pointIndex]);
      });
      _mapController.move(_currentLocation, 15.0);
    });
  }

  void _stopNavigation() {
    _simulationTimer?.cancel();
    setState(() => _isNavigating = false);
    _speak("Navigation stopped.");
  }

  @override
  Widget build(BuildContext context) {
    final double stepRemainingMeters = distanceKm * 1000 / (steps.isEmpty ? 1 : steps.length);

    return Scaffold(
      appBar: AppBar(
        title: Text(_destinationName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: _isMuted ? 'Unmute voice guidance' : 'Mute voice guidance',
            icon: Icon(
              _isMuted ? Icons.volume_off : Icons.volume_up,
              color: _isMuted ? Colors.red.shade400 : Colors.blue,
            ),
            onPressed: _toggleMute,
          ),
        ],
      ),
      body: Stack(
        children: [
          // FULL SCREEN MAP
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 11,
              onLongPress: _onMapLongPress,
            ),
            children: [
              buildDootTileLayer(),
              if (_showDangerZones)
                CircleLayer(
                  circles: _riskZones.map((rz) {
                    return CircleMarker(
                      point: rz['pos'],
                      radius: rz['radius'],
                      useRadiusInMeter: true,
                      color: Colors.red.withValues(alpha: 0.35),
                      borderColor: Colors.red,
                      borderStrokeWidth: 2,
                    );
                  }).toList(),
                ),
              if (_showSafeCorridors)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: polylinePoints.isEmpty ? [_currentLocation, _destination] : polylinePoints,
                      strokeWidth: 6,
                      color: Colors.blue.shade800,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    child: const Icon(Icons.navigation, color: Colors.blue, size: 34),
                  ),
                  Marker(
                    point: _destination,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 38),
                  ),
                  if (_showReliefCamps)
                    ..._shelters.map((s) {
                      return Marker(
                        point: s['pos'],
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _destination = s['pos'];
                              _destinationName = s['name'];
                            });
                            _fetchOSRMRoute();
                            _speak("Shelter selected: ${s['name']}");
                          },
                          child: const Icon(Icons.night_shelter, color: Colors.orange, size: 30),
                        ),
                      );
                    }),
                ],
              ),
            ],
          ),

          // TOP SEARCH BAR OVERLAY
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search shelter / destination...',
                          prefixIcon: Icon(Icons.search, color: Colors.blue, size: 20),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _searchAndRoute(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, color: Colors.blue, size: 20),
                      onPressed: _searchAndRoute,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // RIGHT FLOATING ACTION BUTTONS (GOOGLE MAPS STYLE LIVE LOCATION & START/STOP)
          Positioned(
            right: 12,
            bottom: 75,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'live_location_pin',
                  backgroundColor: Colors.white,
                  tooltip: 'Pin Live Location',
                  onPressed: _pinLiveLocation,
                  child: const Icon(Icons.my_location, color: Colors.blue),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'start_nav_btn',
                  backgroundColor: _isNavigating ? Colors.red : Colors.green.shade700,
                  onPressed: _isNavigating ? _stopNavigation : _startNavigation,
                  icon: Icon(_isNavigating ? Icons.stop : Icons.navigation, color: Colors.white),
                  label: Text(
                    _isNavigating ? 'Stop' : 'Start',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // ONE STEP AT A TIME GUIDANCE OVERLAY (POSITIONED LEFT AT BOTTOM JUST BELOW START BUTTON LEVEL)
          Positioned(
            left: 10,
            bottom: 70,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.58,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                border: Border.all(color: Colors.blue.shade400, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.turn_right, color: Colors.greenAccent, size: 22),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${stepRemainingMeters.toStringAsFixed(0)}m Ahead',
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps.isNotEmpty ? steps[_currentStepIndex] : 'DEPART ON SAFE ROUTE',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // BOTTOM INTERACTIVE LEGEND TOGGLE BUTTONS
          Positioned(
            bottom: 12,
            left: 10,
            right: 10,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInteractiveLegend(
                      label: 'Danger Zone',
                      isActive: _showDangerZones,
                      iconWidget: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      ),
                      onTap: () {
                        setState(() => _showDangerZones = !_showDangerZones);
                        if (_showDangerZones && _riskZones.isNotEmpty) {
                          _mapController.move(_riskZones.first['pos'], 12.0);
                        }
                      },
                    ),
                    _buildInteractiveLegend(
                      label: 'Safe Corridor',
                      isActive: _showSafeCorridors,
                      iconWidget: const Icon(Icons.alt_route, size: 14, color: Colors.blue),
                      onTap: () {
                        setState(() => _showSafeCorridors = !_showSafeCorridors);
                        if (_showSafeCorridors && polylinePoints.isNotEmpty) {
                          _mapController.move(polylinePoints.first, 12.0);
                        }
                      },
                    ),
                    _buildInteractiveLegend(
                      label: 'Relief Camp',
                      isActive: _showReliefCamps,
                      iconWidget: const Icon(Icons.night_shelter, size: 14, color: Colors.orange),
                      onTap: () {
                        setState(() => _showReliefCamps = !_showReliefCamps);
                        if (_showReliefCamps && _shelters.isNotEmpty) {
                          _mapController.move(_shelters.first['pos'], 12.0);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveLegend({
    required String label,
    required bool isActive,
    required Widget iconWidget,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isActive ? Colors.blue.shade300 : Colors.transparent),
        ),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.blue.shade900 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 4: NDRF RESCUE COMMAND CENTER (AUTO REMOVE RESCUED & BACKEND PERSISTENCE)
// ============================================================================
class NDRFCommandScreen extends StatefulWidget {
  const NDRFCommandScreen({super.key});

  @override
  State<NDRFCommandScreen> createState() => _NDRFCommandScreenState();
}

class _NDRFCommandScreenState extends State<NDRFCommandScreen> {
  List<Map<String, dynamic>> _dbAlerts = [];
  List<Map<String, dynamic>> _localPackets = [];
  StreamSubscription<List<Map<String, dynamic>>>? _meshSubscription;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _localPackets = BleMeshService().getReceivedPackets();
    _meshSubscription = BleMeshService().onMeshPacketsChanged.listen((packets) {
      if (mounted) {
        setState(() {
          _localPackets = packets;
        });
      }
    });
    _fetchSupabaseAlerts();
  }

  @override
  void dispose() {
    _meshSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchSupabaseAlerts() async {
    setState(() => isLoading = true);
    try {
      final data = await supabase.from('distress_alerts').select().order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          // Filter out RESCUED items so they clear from active dashboard
          _dbAlerts = List<Map<String, dynamic>>.from(data).where((a) => a['status'] != 'RESCUED').toList();
        });
      }
    } catch (e) {
      debugPrint("Supabase fetch error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _updateAlertStatus(String dbId, String status, {String? meshAlertId}) async {
    try {
      // 1. Update Persistent Backend Database Record
      await supabase.from('distress_alerts').update({'status': status}).eq('id', dbId);

      // 2. Remove Rescued Item from Dashboard Screen View to prevent clutter
      if (status == 'RESCUED') {
        setState(() {
          _dbAlerts.removeWhere((a) => a['id']?.toString() == dbId);
          if (meshAlertId != null) {
            BleMeshService().removePacketById(meshAlertId);
            _localPackets = BleMeshService().getReceivedPackets();
          }
        });
      } else {
        _fetchSupabaseAlerts();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'RESCUED'
                ? 'Victim Rescued! Cleared from active dashboard & saved to backend.'
                : 'Status updated to $status'),
            backgroundColor: status == 'RESCUED' ? Colors.green : Colors.blue,
          ),
        );
      }
    } catch (e) {
      debugPrint("Status update failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalActiveDistress = _dbAlerts.length + _localPackets.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NDRF Rescue Command Center', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _localPackets = BleMeshService().getReceivedPackets();
              });
              _fetchSupabaseAlerts();
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LiveBroadcastBannerWidget(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$totalActiveDistress', style: const TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.bold)),
                              const Text('Active SOS Distress Calls', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Icon(Icons.security, color: Colors.red, size: 30),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Incoming Distress Signals:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      if (_localPackets.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade700),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cell_tower, size: 12, color: Colors.amber.shade900),
                              const SizedBox(width: 4),
                              Text(
                                '${_localPackets.length} Mesh Live',
                                style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: isLoading && _localPackets.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            children: [
                              ..._localPackets.map((alert) {
                                final isSiren = alert['status'] == 'ACTIVE_SIREN' || alert['alertId'].toString().startsWith('SIREN');
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _buildDistressCard(
                                    id: alert['alertId'] ?? 'SOS-MESH',
                                    phone: '${alert['phone']} • Lat: ${(alert['latitude'] as num?)?.toStringAsFixed(2)}, Lng: ${(alert['longitude'] as num?)?.toStringAsFixed(2)}',
                                    msg: alert['message'] ?? 'Emergency offline mesh distress broadcast',
                                    time: alert['time'] ?? alert['timestamp'] ?? 'Realtime Mesh',
                                    status: isSiren ? 'ACTIVE SIREN' : (alert['status'] ?? 'PENDING'),
                                    statusColor: isSiren ? Colors.deepOrange.shade800 : Colors.red.shade700,
                                    isMesh: true,
                                    isSiren: isSiren,
                                    meshAlertId: alert['alertId'],
                                  ),
                                );
                              }),
                              ..._dbAlerts.map((alert) {
                                final statusStr = alert['status'] ?? 'PENDING';
                                Color badgeColor = Colors.red;
                                if (statusStr == 'DISPATCHED') badgeColor = Colors.orange;
                                if (statusStr == 'CRITICAL') badgeColor = Colors.purple;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _buildDistressCard(
                                    id: alert['name'] ?? alert['phone'] ?? 'SOS-DB',
                                    phone: '${alert['phone']} • Lat: ${(alert['latitude'] as num?)?.toStringAsFixed(2)}, Lng: ${(alert['longitude'] as num?)?.toStringAsFixed(2)}',
                                    msg: alert['message'] ?? 'Distress signal received',
                                    time: 'Cloud Synced',
                                    status: statusStr,
                                    statusColor: badgeColor,
                                    dbId: alert['id']?.toString(),
                                  ),
                                );
                              }),
                            ],
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

  Widget _buildDistressCard({
    required String id,
    required String phone,
    required String msg,
    required String time,
    required String status,
    required Color statusColor,
    bool isMesh = false,
    bool isSiren = false,
    String? dbId,
    String? meshAlertId,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isMesh ? BorderSide(color: isSiren ? Colors.deepOrange : Colors.amber.shade600, width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: statusColor,
                  radius: 18,
                  child: Icon(isSiren ? Icons.campaign : (isMesh ? Icons.cell_tower : Icons.warning_amber), color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text('$id • $phone', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          if (isMesh) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSiren ? const Color(0xFFFFEDD5) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isSiren ? 'SIREN RELAY' : 'BLE MESH',
                                style: TextStyle(color: isSiren ? Colors.deepOrange.shade900 : Colors.amber.shade900, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(msg, style: const TextStyle(color: Colors.black87, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text('Time: $time', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (dbId != null) _updateAlertStatus(dbId, 'DISPATCHED');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Mark Dispatch', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (dbId != null) {
                        _updateAlertStatus(dbId, 'RESCUED', meshAlertId: meshAlertId);
                      } else if (meshAlertId != null) {
                        setState(() {
                          BleMeshService().removePacketById(meshAlertId);
                          _localPackets = BleMeshService().getReceivedPackets();
                        });
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Mark Rescue', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 5: DYNAMIC PROFILE SCREEN
// ============================================================================
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emergencyContactController = TextEditingController();

  bool _isEditing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('user_name') ?? 'User';
      _phoneController.text = prefs.getString('user_phone') ?? '';
      _emergencyContactController.text = prefs.getString('emergency_contact') ?? '112 (National Emergency)';
      _isLoading = false;
    });
  }

  Future<void> _saveUserProfile() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final emergency = _emergencyContactController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and Phone Number cannot be empty.')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    await prefs.setString('user_phone', phone);
    await prefs.setString('emergency_contact', emergency);

    setState(() => _isEditing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'User Settings & Emergency Profile',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit, color: Colors.blue),
            onPressed: () {
              if (_isEditing) {
                _saveUserProfile();
              } else {
                setState(() => _isEditing = true);
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LiveBroadcastBannerWidget(),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.blue.shade100,
                            child: Icon(Icons.person, size: 36, color: Colors.blue.shade800),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nameController.text,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _phoneController.text.isNotEmpty ? _phoneController.text : 'No phone set',
                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: const Text(
                                    'ACTIVE BLE/LORA NODE',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PERSONAL INFORMATION',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          TextField(
                            controller: _nameController,
                            enabled: _isEditing,
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _phoneController,
                            enabled: _isEditing,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _emergencyContactController,
                            enabled: _isEditing,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Emergency Secondary Contact',
                              prefixIcon: const Icon(Icons.contact_phone_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isEditing)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('SAVE PROFILE CHANGES', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _saveUserProfile,
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'EVACUATION & DEVICE PREFERENCES',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.bluetooth, color: Colors.blue),
                          title: const Text('Offline Mesh Relay Node', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: const Text('Forward emergency signals for nearby victims', style: TextStyle(fontSize: 11)),
                          trailing: Switch(value: true, onChanged: (_) {}),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.volume_up, color: Colors.orange),
                          title: const Text('High-Decibel Siren Alerts', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: const Text('Allow incoming mesh signals to trigger local horn', style: TextStyle(fontSize: 11)),
                          trailing: Switch(value: true, onChanged: (_) {}),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}