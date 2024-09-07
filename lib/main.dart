// import 'package:crossdevice/firebase_options.dart';
// import 'home_screen.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await Firebase.initializeApp(
//     options: DefaultFirebaseOptions.currentPlatform,
//   );
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: "Cross-device",
//       theme: ThemeData(
//         primarySwatch: Colors.indigo,
//       ),
//       home: HomeScreen(),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:convert';
import 'dart:io';

void main() async {
  runApp(WifiSyncApp());
}

class WifiSyncApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Cross-device",
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: WifiSyncHome(),
    );
  }
}

class WifiSyncHome extends StatefulWidget {
  @override
  _WifiSyncHomeState createState() => _WifiSyncHomeState();
}

class _WifiSyncHomeState extends State<WifiSyncHome> {
  final NetworkInfo _networkInfo = NetworkInfo();
  WebSocket? _webSocket;
  bool _isConnected = false;
  String _localIp = '';
  String _debugInfo = '';
  HttpServer? _server;
  TextEditingController _messageController = TextEditingController();
  List<String> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    _getLocalIp();
    _startServer();
  }

  void _getLocalIp() async {
    String? ip = await _networkInfo.getWifiIP();
    if (ip != null) {
      setState(() {
        _localIp = ip;
        _addDebugInfo('Local IP: $ip');
      });
    } else {
      _addDebugInfo('Failed to get local IP');
    }
  }

  void _startServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _addDebugInfo('Server started on port 8080');
      _server!.transform(WebSocketTransformer()).listen(_handleConnection);
    } catch (e) {
      _addDebugInfo('Failed to start server: $e');
    }
  }

  void _handleConnection(WebSocket webSocket) {
    _addDebugInfo('Client connected');
    _webSocket = webSocket;
    setState(() {
      _isConnected = true;
    });
    webSocket.listen(
      (message) {
        _addDebugInfo('Received message: $message');
        setState(() {
          _chatMessages.add('Otro: $message');
        });
      },
      onError: (error) => _addDebugInfo('WebSocket error: $error'),
      onDone: () {
        _addDebugInfo('WebSocket connection closed');
        setState(() {
          _isConnected = false;
        });
      },
    );
  }

  void _connectToDevice(String data) async {
    Map<String, dynamic> connectionInfo = json.decode(data);
    String ip = connectionInfo['ip'];
    _addDebugInfo('Attempting to connect to: $ip');
    try {
      _webSocket = await WebSocket.connect('ws://$ip:8080');
      _addDebugInfo('Connected to: $ip');
      setState(() {
        _isConnected = true;
      });
      _webSocket!.listen(
        (message) {
          _addDebugInfo('Received message: $message');
          setState(() {
            _chatMessages.add('Otro: $message');
          });
        },
        onError: (error) => _addDebugInfo('WebSocket error: $error'),
        onDone: () {
          _addDebugInfo('WebSocket connection closed');
          setState(() {
            _isConnected = false;
          });
        },
      );
    } catch (e) {
      _addDebugInfo('Failed to connect: $e');
    }
  }

  void _sendMessage() {
    if (_webSocket != null && _webSocket!.readyState == WebSocket.open) {
      String message = _messageController.text;
      _webSocket!.add(message);
      _addDebugInfo('Message sent: $message');
      setState(() {
        _chatMessages.add('Tú: $message');
        _messageController.clear();
      });
    } else {
      _addDebugInfo('Cannot send message: not connected');
    }
  }

  void _addDebugInfo(String info) {
    setState(() {
      _debugInfo += '$info\n';
    });
    print(info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cross-device')),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _isConnected ? _buildConnectedView() : _buildConnectionView(),
              SizedBox(height: 20),
              // Text('Console:',
              //     style: TextStyle(fontWeight: FontWeight.bold)),
              // Container(
              //   height: 200,
              //   child: SingleChildScrollView(
              //     child: Text(_debugInfo),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                content: Container(
                  width: 300,
                  height: 300,
                  child: QrImageView(
                    data: json.encode({'ip': _localIp}),
                    version: QrVersions.auto,
                    size: 300.0,
                  ),
                ),
              ),
            );
          },
          child: Text('Mostrar mi código QR'),
        ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => QRViewExample(
                  onQRScanned: (String data) {
                    _connectToDevice(data);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            );
          },
          child: Text('Escanear código QR'),
        ),
      ],
    );
  }

  Widget _buildConnectedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Conectado'),
        SizedBox(height: 20),
        Container(
          height: 300,
          child: ListView.builder(
            itemCount: _chatMessages.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(_chatMessages[index]),
              );
            },
          ),
        ),
        SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Escribe tu mensaje...',
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _webSocket?.close();
    _server?.close();
    _messageController.dispose();
    super.dispose();
  }
}

class QRViewExample extends StatefulWidget {
  final Function(String) onQRScanned;

  QRViewExample({required this.onQRScanned});

  @override
  State<StatefulWidget> createState() => _QRViewExampleState();
}

class _QRViewExampleState extends State<QRViewExample> {
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QRView(
        key: qrKey,
        onQRViewCreated: _onQRViewCreated,
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null) {
        widget.onQRScanned(scanData.code!);
        controller.dispose();
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
