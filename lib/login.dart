import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'home.dart';

class BiometricService {
  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  Future<bool> isBiometricAvailable() async {
    final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
    return canAuthenticateWithBiometrics || await auth.isDeviceSupported();
  }

  Future<IconData> getBiometricIcon() async {
    List<BiometricType> availableBiometrics = await auth.getAvailableBiometrics();
    if (availableBiometrics.contains(BiometricType.face)) {
      return Icons.face;
    } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;
    }
    return Icons.lock_open;
  }

  Future<bool> authenticate() async {
    try {
      return await auth.authenticate(
        localizedReason: 'Authenticate to access Palm Vibe',
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

  Future<void> setManualLogout(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('manual_logout', value);
  }

  Future<bool> shouldAutoAuthenticate() async {
    final prefs = await SharedPreferences.getInstance();
    bool isEnabled = prefs.getBool('biometric_enabled') ?? false;
    bool manualLogout = prefs.getBool('manual_logout') ?? false;
    return isEnabled && !manualLogout;
  }
}

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({Key? key}) : super(key: key);
  @override
  _ServerConfigScreenState createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final BiometricService _biometricService = BiometricService();

  bool _isLoading = false;
  String _status = '';
  String _serverIP = '';
  String _privateIP = '';
  String _ngrokUrl = '';
  String _serverPort = '8080';
  String _currentVersion = '1.0.0';
  int _tapCount = 0;
  IconData _biometricIcon = Icons.fingerprint;
  bool _canShowBiometric = false;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
    _loadAppVersion();
    _initBiometrics();
  }

  @override
  void dispose() {
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initBiometrics() async {
    bool available = await _biometricService.isBiometricAvailable();
    if (available) {
      IconData icon = await _biometricService.getBiometricIcon();
      bool shouldAuto = await _biometricService.shouldAutoAuthenticate();
      setState(() {
        _biometricIcon = icon;
        _canShowBiometric = true;
      });
      if (shouldAuto) {
        _handleBiometricLogin();
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    bool authenticated = await _biometricService.authenticate();
    if (authenticated) {
      var creds = await _biometricService.getCredentials();
      if (creds['username'] != null && creds['password'] != null) {
        setState(() {
          _usernameController.text = creds['username']!;
          _passwordController.text = creds['password']!;
        });
        _testConnection();
      }
    }
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _usernameController.text = prefs.getString('username') ?? '';
      _passwordController.text = prefs.getString('password') ?? '';
    });
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() => _currentVersion = packageInfo.version);
  }

  void _showLocalIpDialog() {
    final TextEditingController localIpController = TextEditingController(text: _privateIP.isNotEmpty ? _privateIP : _serverIP);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Manual IP Entry', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: localIpController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '192.168.1.XX',
            hintStyle: TextStyle(color: Colors.grey),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purple)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() => _privateIP = localIpController.text);
              Navigator.pop(context);
              _testConnection();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() { 
      _isLoading = true; 
      _status = 'Initiating connection...'; 
    });

    try {
      final response = await http.get(
        Uri.parse('https://palmvibe-59ae2-default-rtdb.europe-west1.firebasedatabase.app/serverInfo.json'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body);
        _serverIP = data['ip']?.toString() ?? '';
        _privateIP = data['privateIp']?.toString() ?? _privateIP;
        _ngrokUrl = data['ngrokUrl']?.toString() ?? '';
        _serverPort = data['port']?.toString() ?? '8080';
      }
    } catch (e) {}

    List<Map<String, String>> connectionAttempts = [];
    if (_privateIP.isNotEmpty) connectionAttempts.add({'url': 'http://$_privateIP:$_serverPort', 'type': 'Local Network'});
    if (_serverIP.isNotEmpty) connectionAttempts.add({'url': 'http://$_serverIP:$_serverPort', 'type': 'Cloud Server'});
    if (_ngrokUrl.isNotEmpty && _ngrokUrl != 'Unavailable') connectionAttempts.add({'url': _ngrokUrl, 'type': 'Remote Tunnel'});

    String? successfulIp;
    for (var attempt in connectionAttempts) {
      bool success = await _attemptLogin(attempt['url']!, attempt['type']!);
      if (success) {
        final uri = Uri.parse(attempt['url']!);
        successfulIp = uri.host;
        break;
      }
    }

    if (successfulIp != null) {
      await _biometricService.saveCredentials(_usernameController.text, _passwordController.text);
      await _biometricService.setManualLogout(false);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', _usernameController.text);
      await prefs.setString('password', _passwordController.text);
      await prefs.setString('server_ip', successfulIp);
      if (mounted) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen(
              serverIp: successfulIp!,
              serverPort: _serverPort,
              username: _usernameController.text,
              password: _passwordController.text
            ))
        );
      }
    } else {
      setState(() {
        _status = 'Could not reach server.';
        _isLoading = false;
      });
    }
  }

  Future<bool> _attemptLogin(String baseUrl, String type) async {
    try {
      setState(() => _status = 'Connecting to $type...');
      final auth = 'Basic ${base64Encode(utf8.encode('${_usernameController.text}:${_passwordController.text}'))}';
      final url = Uri.parse('$baseUrl/api/test');
      final response = await http.get(url, headers: {
        'Authorization': auth,
        'ngrok-skip-browser-warning': 'true'
      }).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/brand.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      _tapCount++;
                      if (_tapCount >= 7) {
                        _tapCount = 0;
                        _showLocalIpDialog();
                      }
                    },
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purple.withOpacity(0.4),
                            blurRadius: 25,
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(55),
                        child: Image.asset('assets/icon/app_icon.png'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'PALM VIBE',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sign In',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _usernameController,
                          focusNode: _usernameFocus,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            labelStyle: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.02),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Colors.purple, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 16),
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_passwordFocus),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.02),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Colors.purple, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 16),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _testConnection(),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _testConnection,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                              color: Colors.white, strokeWidth: 2))
                                      : const Text('CONTINUE',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1)),
                                ),
                              ),
                            ),
                            if (_canShowBiometric) ...[
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 50,
                                width: 50,
                                child: IconButton(
                                  onPressed: _handleBiometricLogin,
                                  icon: Icon(_biometricIcon, color: Colors.purple, size: 28),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(0.02),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_status.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              _status,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: _status.contains('Connected')
                                      ? Colors.green
                                      : Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Palm Vibe v$_currentVersion',
                style: const TextStyle(color: Colors.white10, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
