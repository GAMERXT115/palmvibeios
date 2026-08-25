import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_database/firebase_database.dart';
import 'main.dart' show isFirebaseInitialized;
import 'home.dart';
import 'downloads.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _connectBtnFocus = FocusNode();

  bool _isLoading = false;
  String _status = '';
  bool _isConnected = false;
  String _serverIP = '';
  String _serverPort = '8080';
  bool _rememberMe = false;
  int _tapCount = 0;
  String _serverMessage = '';
  bool _showServerMessage = false;
  
  bool _hasUpdate = false;
  String _updateMessage = '';
  String _updateTitle = 'Update Available';
  bool _forceUpdate = false;
  String _currentVersion = '1.0.0';
  String? _updateUrl;
  int _updateFileSize = 0;
  bool _isDownloadingUpdate = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeConnection();
    _loadSavedConfig();
    _loadAppVersion();
    _requestInstallPermission();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _connectBtnFocus.dispose();
    super.dispose();
  }

  Future<void> _initializeConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final manualIP = prefs.getString('server_ip');
    
    if (manualIP != null && manualIP.isNotEmpty) {
      setState(() {
        _serverIP = manualIP;
        _serverPort = prefs.getString('server_port') ?? '8080';
      });
      _fetchServerMessage();
    } else {
      _fetchServerInfoFromFirebase();
    }
  }

  Future<void> _fetchServerInfoFromFirebase() async {
    try {
      if (isFirebaseInitialized) {
        final databaseReference = FirebaseDatabase.instance.ref();
        final snapshot = await databaseReference.child('serverInfo').get();
        
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            _serverIP = (data['privateIp'] ?? data['ip']).toString();
            _serverPort = data['port'].toString();
          });
          _fetchServerMessage();
        }
      }
    } catch (e) {}
  }

  Future<void> _requestInstallPermission() async {
    if (Platform.isAndroid) {
      await Permission.requestInstallPackages.request();
    }
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _currentVersion = packageInfo.version;
    });
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberMe = prefs.getBool('remember_me') ?? false;
      if (_rememberMe) {
        _usernameController.text = prefs.getString('username') ?? '';
        _passwordController.text = prefs.getString('password') ?? '';
      }
    });
  }

  Future<void> _fetchServerMessage() async {
    if (_serverIP.isEmpty) return;
    try {
      final url = Uri.parse('http://$_serverIP:$_serverPort/api/server-message');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['message'] != null) {
          setState(() {
            _serverMessage = data['message'];
            _showServerMessage = _serverMessage.isNotEmpty;
          });
        }
      }
    } catch (e) {}
  }

  Future<void> _checkForUpdates() async {
    try {
      final url = Uri.parse('http://$_serverIP:$_serverPort/api/check-update?version=$_currentVersion');
      final headers = <String, String>{
        'Authorization': _authHeader,
        'App-Version': _currentVersion,
      };
      
      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _hasUpdate = data['hasUpdate'] ?? false;
          _updateMessage = data['updateMessage'] ?? 'A new update is available.';
          _updateTitle = data['updateTitle'] ?? 'Update Available';
          _forceUpdate = data['forceUpdate'] ?? false;
          _updateUrl = data['updateUrl'];
          _updateFileSize = data['fileSize'] ?? 0;
        });
        
        if (_hasUpdate) {
          await _showUpdateDialog(_forceUpdate);
        }
      }
    } catch (e) {}
  }

  Future<void> _downloadUpdate(StateSetter dialogSetState) async {
    if (_updateUrl == null) return;
    
    final url = Uri.parse('http://$_serverIP:$_serverPort$_updateUrl');
    
    setState(() {
      _isDownloadingUpdate = true;
      _downloadProgress = 0.0;
    });
    
    dialogSetState(() {
      _isDownloadingUpdate = true;
      _downloadProgress = 0.0;
    });
    
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/update.apk';
    
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
      
      final client = http.Client();
      final request = http.Request('GET', url);
      request.headers['Authorization'] = _authHeader;
      
      final response = await client.send(request);
      final totalBytes = response.contentLength ?? _updateFileSize;
      var downloadedBytes = 0;
      
      List<int> bytes = [];
      await for (var chunk in response.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          dialogSetState(() {
            _downloadProgress = downloadedBytes / totalBytes;
          });
        }
      }
      
      await file.writeAsBytes(bytes);
      
      if (Platform.isAndroid) {
        await OpenFile.open(filePath);
      }
    } finally {
      setState(() => _isDownloadingUpdate = false);
      dialogSetState(() => _isDownloadingUpdate = false);
    }
  }

  Future<void> _showUpdateDialog(bool forceUpdate) async {
    return showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: Text(_updateTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_updateMessage),
                  if (_isDownloadingUpdate) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 8),
                    Text('${(_downloadProgress * 100).toStringAsFixed(1)}%'),
                  ],
                ],
              ),
              actions: [
                if (!_isDownloadingUpdate)
                  TextButton(
                    onPressed: () => _downloadUpdate(dialogSetState),
                    child: const Text('Download'),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (forceUpdate) SystemNavigator.pop();
                  },
                  child: Text(forceUpdate ? 'Exit' : 'Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String get _authHeader => 'Basic ${base64Encode(utf8.encode('${_usernameController.text}:${_passwordController.text}'))}';

  Future<void> _testConnection() async {
    if (_serverIP.isEmpty) {
      setState(() => _status = 'No Server IP configured');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Connecting to $_serverIP...';
    });

    try {
      final url = Uri.parse('http://$_serverIP:$_serverPort/api/test');
      final response = await http.get(url, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true'
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_me', _rememberMe);
        await prefs.setString('server_ip', _serverIP);
        await prefs.setString('server_port', _serverPort);

        if (_rememberMe) {
          await prefs.setString('username', _usernameController.text);
          await prefs.setString('password', _passwordController.text);
        }

        setState(() {
          _status = 'Connected!';
          _isLoading = false;
          _isConnected = true;
        });

        await _checkForUpdates();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                serverIp: _serverIP,
                serverPort: _serverPort,
                username: _usernameController.text,
                password: _passwordController.text,
              ),
            ),
          );
        }
      } else {
        setState(() {
          _status = 'Error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Failed to connect: $e';
        _isLoading = false;
      });
    }
  }

  void _showLocalIpDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final lastIp = prefs.getString('server_ip') ?? '';
    final controller = TextEditingController(text: lastIp);
    final DateTime openTime = DateTime.now();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => GestureDetector(
        onTap: () {
          if (DateTime.now().difference(openTime).inSeconds >= 1) {
            Navigator.pop(context);
          }
        },
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: AlertDialog(
                title: const Text('Enter Server IP'),
                content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(hintText: "192.168.x.x"),
                  keyboardType: TextInputType.url,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context), 
                    child: const Text('Cancel')
                  ),
                  TextButton(
                    onPressed: () async {
                      final newIp = controller.text.trim();
                      await prefs.setString('server_ip', newIp);
                      setState(() => _serverIP = newIp);
                      Navigator.pop(context);
                      if (newIp.isNotEmpty) {
                        _fetchServerMessage();
                      } else {
                        _fetchServerInfoFromFirebase();
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Palm Vibe'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DownloadsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  _tapCount++;
                  if (_tapCount == 7) {
                    _tapCount = 0;
                    _showLocalIpDialog();
                  }
                },
                child: const Icon(Icons.connected_tv, size: 80, color: Colors.purple),
              ),
              const SizedBox(height: 20),
              const Text(
                'Login using your credentials provided by HamTech',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _usernameController,
                focusNode: _usernameFocus,
                decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              CheckboxListTile(
                title: const Text("Remember Me"),
                value: _rememberMe,
                onChanged: (val) => setState(() => _rememberMe = val ?? false),
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      focusNode: _connectBtnFocus,
                      onPressed: _testConnection,
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: const Text('Connect'),
                    ),
              const SizedBox(height: 20),
              Text(_status, style: TextStyle(color: _isConnected ? Colors.green : Colors.red), textAlign: TextAlign.center),
              if (_showServerMessage)
                Container(
                  margin: const EdgeInsets.only(top: 20),
                  padding: const EdgeInsets.all(10),
                  color: Colors.purple.withOpacity(0.3),
                  child: Text(_serverMessage),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
