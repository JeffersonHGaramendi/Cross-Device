import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:convert';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
