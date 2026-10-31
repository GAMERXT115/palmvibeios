import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'splash_screen.dart';
import 'login.dart';
import 'video_player.dart';
import 'package:firebase_database/firebase_database.dart';

class CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 10
      ..idleTimeout = const Duration(minutes: 5);
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool isFirebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Firebase initialization timed out');
        },
      );
      isFirebaseInitialized = true;
    } else {
      isFirebaseInitialized = true;
    }
  } catch (e) {}

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  HttpOverrides.global = CustomHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Timer? _castTimer;
  int? _lastCommandId;

  @override
  void initState() {
    super.initState();
    _startCastListener();
  }

  void _startCastListener() {
    _castTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkCastStatus();
    });
  }

  Future<void> _checkCastStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final String user = prefs.getString('username') ?? prefs.getString('pv_user') ?? "";
    final String pass = prefs.getString('password') ?? prefs.getString('pv_pass') ?? "";
    final String myDeviceName = "Mobile ${Platform.operatingSystem}";

    if (user.isEmpty || pass.isEmpty) return;

    String? localIp;
    String? publicIp;
    String? ngrokUrl;
    String port = "8080";

    try {
      final snapshot = await FirebaseDatabase.instance.ref().child('serverInfo').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        localIp = data['privateIp']?.toString();
        publicIp = data['ip']?.toString();
        ngrokUrl = data['ngrokUrl']?.toString();
        port = data['port']?.toString() ?? "8080";
      }
    } catch (e) {
      localIp = prefs.getString('server_ip');
    }

    List<String> candidates = [];
    if (localIp != null && localIp.isNotEmpty) candidates.add("http://$localIp:$port");
    if (publicIp != null && publicIp.isNotEmpty) candidates.add("http://$publicIp:$port");
    if (ngrokUrl != null && ngrokUrl.isNotEmpty && ngrokUrl != 'Unavailable') candidates.add(ngrokUrl);

    String? successfulBaseUrl;
    final auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

    for (String url in candidates) {
      try {
        final testResponse = await http.get(
          Uri.parse('$url/api/cast/status?deviceName=${Uri.encodeComponent(myDeviceName)}'),
          headers: {
            'Authorization': auth,
            'ngrok-skip-browser-warning': 'true',
          },
        ).timeout(const Duration(seconds: 2));

        if (testResponse.statusCode == 200) {
          successfulBaseUrl = url;
          final data = json.decode(testResponse.body);
          if (data['success'] == true) {
            final String action = data['action'] ?? '';
            final int commandId = data['commandId'] ?? 0;
            final String videoPath = data['videoPath'] ?? '';
            final String subtitlePath = data['subtitlePath'] ?? '';

            if (action == 'START_CAST') {
              if (_lastCommandId == null || commandId > _lastCommandId!) {
                _lastCommandId = commandId;

                bool isAlreadyPlaying = false;
                navigatorKey.currentState?.popUntil((route) {
                  if (route.settings.name == '/video_player') {
                    isAlreadyPlaying = true;
                  }
                  return true;
                });

                if (!isAlreadyPlaying) {
                  _triggerPlayback(
                    videoPath,
                    data['timestamp'] ?? 0,
                    data['title'] ?? 'Casted Video',
                    successfulBaseUrl,
                    user,
                    pass,
                    subtitlePath,
                  );
                }
              }
            } else if (action == 'STOP_CAST') {
              if (_lastCommandId != null && commandId > _lastCommandId!) {
                _lastCommandId = commandId;
                navigatorKey.currentState?.popUntil((route) => route.isFirst);
              }
            }
          }
          break;
        }
      } catch (e) {
        continue;
      }
    }
  }

  void _triggerPlayback(String path, int seek, String title, String baseUrl, String user, String pass, String subtitlePath) {
    final videoUrl = '$baseUrl/api/stream?path=${Uri.encodeComponent(path)}';

    List<String> initialSubs = [];
    if (subtitlePath.isNotEmpty) {
      initialSubs.add('$baseUrl/api/subtitle?path=${Uri.encodeComponent(subtitlePath)}');
    }

    if (navigatorKey.currentState == null) return;

    final uri = Uri.parse(baseUrl);
    final ip = uri.host;
    final port = uri.port.toString();

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/video_player'),
        builder: (context) => VideoPlayerScreen(
          videoUrl: '$videoUrl&start=$seek',
          subtitleUrls: initialSubs,
          title: title,
          serverIp: ip,
          serverPort: port,
          username: user,
          password: pass,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _castTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Palm Vibe',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.standard,
        canvasColor: Colors.black,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      ),
      home: const SplashScreen(nextScreen: ServerConfigScreen()),
      debugShowCheckedModeBanner: false,
    );
  }
}
