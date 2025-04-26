// lib/services/websocket_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/connection_state.dart';

class WebSocketManager {
  final Map<String, WebSocket> _connections = {};
  final Map<String, ConnectionState> _connectionStates = {};
  final Map<String, DateTime> _lastPongTimes = {};
  HttpServer? _server;
  Timer? _pingTimer;

  final Duration pingInterval = Duration(seconds: 5);
  final void Function(String message, String connectionId)? onMessageReceived;
  final void Function(String connectionId)? onDisconnected;
  final void Function(String connectionId)? onConnected;

  WebSocketManager({
    this.onMessageReceived,
    this.onDisconnected,
    this.onConnected,
  });

  Future<void> startServer({int port = 8080}) async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.transform(WebSocketTransformer()).listen(_handleConnection);
      debugPrint('WebSocket server started on port $port');

      _startPingTimer();
    } catch (e) {
      debugPrint('Failed to start server: $e');
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      _sendPingToAllClients();
      _checkConnectionTimeouts();
    });
  }

  void _sendPingToAllClients() {
    final pingMessage = json.encode({
      'type': 'ping',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    _connections.forEach((id, connection) {
      try {
        connection.add(pingMessage);
      } catch (e) {
        debugPrint('Error sending ping to $id: $e');
        _handleDisconnection(id);
      }
    });
  }

  void _checkConnectionTimeouts() {
    final now = DateTime.now();
    _lastPongTimes.forEach((id, lastPong) {
      if (now.difference(lastPong).inSeconds > 15) {
        debugPrint('Connection timeout for $id');
        _handleDisconnection(id);
      }
    });
  }

  void _handleConnection(WebSocket socket) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    socket.pingInterval = const Duration(seconds: 5);

    _connections[id] = socket;
    _connectionStates[id] = ConnectionState(isConnected: true);
    _lastPongTimes[id] = DateTime.now();

    onConnected?.call(id);
    debugPrint('Client connected: $id');

    socket.listen(
      (message) {
        _lastPongTimes[id] = DateTime.now();
        if (message is String) {
          final decoded = json.decode(message);
          if (decoded['type'] == 'pong') return;

          onMessageReceived?.call(message, id);
        }
      },
      onDone: () => _handleDisconnection(id),
      onError: (e) {
        debugPrint('WebSocket error for $id: $e');
        _handleDisconnection(id);
      },
      cancelOnError: false,
    );
  }

  void _handleDisconnection(String id) {
    _connections[id]?.close();
    _connections.remove(id);
    _connectionStates.remove(id);
    _lastPongTimes.remove(id);

    onDisconnected?.call(id);
    debugPrint('Client disconnected: $id');
  }

  void broadcastMessage(Map<String, dynamic> message) {
    final encoded = json.encode(message);
    for (var conn in _connections.values) {
      try {
        conn.add(encoded);
      } catch (_) {}
    }
  }

  void dispose() {
    _pingTimer?.cancel();
    for (var conn in _connections.values) {
      conn.close();
    }
    _connections.clear();
  }
}
