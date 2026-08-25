import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  Future<bool> isBiometricAvailable() async {
    final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
    final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();
    return canAuthenticate;
  }

  Future<IconData> getBiometricIcon() async {
    List<BiometricType> availableBiometrics = await auth.getAvailableBiometrics();

    if (availableBiometrics.contains(BiometricType.face)) {
      return Icons.face;
    } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;
    } else if (availableBiometrics.contains(BiometricType.iris)) {
      return Icons.remove_red_eye;
    }
    return Icons.lock_open;
  }

  Future<bool> authenticate() async {
    try {
      return await auth.authenticate(
        localizedReason: 'Please authenticate to login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> saveCredentials(String username, String password) async {
    await storage.write(key: 'username', value: username);
    await storage.write(key: 'password', value: password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', true);
  }

  Future<Map<String, String?>> getCredentials() async {
    String? user = await storage.read(key: 'username');
    String? pass = await storage.read(key: 'password');
    return {'username': user, 'password': pass};
  }

  Future<void> clearBiometricFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('manual_logout', true);
  }

  Future<void> setLoginFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('manual_logout', false);
  }

  Future<bool> shouldShowBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    bool isEnabled = prefs.getBool('biometric_enabled') ?? false;
    bool manualLogout = prefs.getBool('manual_logout') ?? false;
    return isEnabled && !manualLogout;
  }
}
