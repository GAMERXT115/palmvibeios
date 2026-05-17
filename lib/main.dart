import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'login.dart';
import 'splash_screen.dart';

class CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 5
      ..idleTimeout = const Duration(minutes: 5);
  }
}

bool isFirebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Firebase initialization timed out');
        },
      );
      isFirebaseInitialized = true;
    } else {
      isFirebaseInitialized = true;
    }
  } catch (e) {
    isFirebaseInitialized = false;
  }

  HttpOverrides.global = CustomHttpOverrides();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const PalmVibeApp());
}

class PalmVibeApp extends StatefulWidget {
  const PalmVibeApp({super.key});

  @override
  State<PalmVibeApp> createState() => _PalmVibeAppState();
}

class _PalmVibeAppState extends State<PalmVibeApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WakelockPlus.enable();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Palm Vibe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.purple,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.purple,
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(nextScreen: LoginPage()),
    );
  }
}
