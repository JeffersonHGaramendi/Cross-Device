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

import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
// import 'dart:math' as math;

import 'package:crossdevice/auth/login_screen.dart';
import 'package:crossdevice/chooserole_screen.dart';
import 'package:crossdevice/qr_code_view.dart';
import 'package:crossdevice/qr_code_view_has_image.dart';
import 'package:crossdevice/scan_qr.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';

import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(WifiSyncApp());
}

class WifiSyncApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Cross-device",
      theme: ThemeData.light(),
      darkTheme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: LoginScreen(),
      //home: WifiSyncHome(),
    );
  }
}

class WifiSyncHome extends StatefulWidget {
  @override
  WifiSyncHomeState createState() => WifiSyncHomeState();
}

class WifiSyncHomeState extends State<WifiSyncHome> {
  final user = FirebaseAuth.instance;
  Map<String, WebSocket> _connections = {};

  HttpServer? _server;

  Uint8List? _imageBytes;
  bool _isSharing = false;
  ui.Image? _uiImage;

  Rect? _initialViewport;

  List<DeviceInfo> connectedDevices = [];
  DeviceInfo? myDevice;

  bool _isReadyToShare = false;
  bool _hasImage = false;
  Map<String, bool> _connectedDevicesReadyState = {};

  bool _allDevicesReady = false;
  double _startHorizontalDragX = 0;
  double _startVerticalDragY = 0;
  bool _isSwipingLeft = false;
  bool _isSwipingRight = false;
  bool _isSwipingDown = false;
  bool _isSwipingUp = false;

  bool _isFreeSliding = true;

  bool _isGestureSyncEnabled = false;

  bool? _isLeader;
  bool _isQRCodeScanned = false;

  Map<String, bool> _devicesSwipingState = {};
  bool _isLocalSwiping = false;

  bool _isSwipeInProgress = false;
  Timer? _swipeTimeoutTimer;
  static const swipeTimeout = Duration(milliseconds: 1000);
  Map<String, DateTime> _lastSwipeTimestamps = {};

  Map<String, ConnectionState> _connectionStates = {};

  Timer? _pingTimer;
  static const pingInterval = Duration(seconds: 5);
  Map<String, DateTime> _lastPongTimes = {};

  final Map<String, bool> _roleSwipeStates = {
    'leader': false,
    'linked': false,
  };

  String? _activeLinkedDeviceId;

  late TransformationController _transformationController;

  String? _direction;

  double? leaderSlideY;
  double? linkedSlideY;
  double? leaderSlideX;
  double? linkedSlideX;

  String? _qrScanError;

  @override
  void initState() {
    super.initState();
    _startServer();
    _startPingTimer();
    _roleSwipeStates['leader'] = false;
    _roleSwipeStates['linked'] = false;
    _transformationController = TransformationController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeLocalDevice(); // Ahora es seguro llamar aquí a MediaQuery
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (timer) {
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
        print('Error sending ping to client $id: $e');
        _handleDisconnection(id);
      }
    });
  }

  void _checkConnectionTimeouts() {
    final now = DateTime.now();
    _lastPongTimes.forEach((id, lastPong) {
      if (now.difference(lastPong).inSeconds > 15) {
        // 15 seconds timeout
        print('Connection timeout for client $id');
        _handleDisconnection(id);
      }
    });
  }

  void _initializeLocalDevice() async {
    final size = MediaQuery.of(context).size;
    String deviceId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    DeviceInfo localDevice = DeviceInfo(
      id: deviceId,
      portion: Rect.zero,
      size: size,
    );
    setState(() {
      myDevice = localDevice;
      connectedDevices.add(localDevice);
    });
    _addDebugInfo('Local device initialized: $deviceId');
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

  // Asegúrate de que esta función esté actualizada para manejar los nuevos tipos de mensajes
  void _handleConnection(WebSocket webSocket) {
    String connectionId = DateTime.now().millisecondsSinceEpoch.toString();

    // Configurar el WebSocket para no cerrarse por inactividad
    webSocket.pingInterval = const Duration(seconds: 5);

    _connections[connectionId] = webSocket;
    _lastPongTimes[connectionId] = DateTime.now();

    _connectionStates[connectionId] =
        ConnectionState(isConnected: true, lastActivity: DateTime.now());

    _addDebugInfo('Client connected: $connectionId');
    print(
        'Nuevo dispositivo conectado. Total dispositivos: ${_connections.length}');

    setState(() {
      _connectedDevicesReadyState[connectionId] = false;
    });

    webSocket.add(json.encode({'type': 'request_screen_size'}));
    _broadcastReadyState();

    webSocket.listen(
      (message) {
        _lastPongTimes[connectionId] = DateTime.now();
        _connectionStates[connectionId]?.lastActivity = DateTime.now();

        try {
          if (message is String) {
            final decoded = json.decode(message);
            if (decoded['type'] == 'pong') {
              return; // Ignorar mensajes pong para el manejo normal
            }
            _handleIncomingMessage(message, connectionId);
          }
        } catch (e) {
          print('Error processing message: $e');
        }
      },
      onError: (error) {
        print('WebSocket error for client $connectionId: $error');
        _handleDisconnection(connectionId);
      },
      onDone: () {
        print('WebSocket connection closed for client $connectionId');
        _handleDisconnection(connectionId);
      },
      cancelOnError: false,
    );
  }

  void _handleDisconnection(String connectionId) {
    if (!_connections.containsKey(connectionId)) return; // Evitar duplicados

    print('Manejando desconexión para cliente: $connectionId');

    _connections.remove(connectionId);
    _connectionStates.remove(connectionId);
    _connectedDevicesReadyState.remove(connectionId);
    _lastPongTimes.remove(connectionId);

    // Remover el dispositivo de la lista de dispositivos conectados
    connectedDevices.removeWhere((device) => device.id == connectionId);

    setState(() {});
    _checkAllDevicesReady();

    print(
        'Dispositivo desconectado. Dispositivos restantes: ${_connections.length}');
  }

  void _connectToDevice(String data) async {
    final uri = Uri.tryParse(data);

    if (uri == null || uri.scheme != 'room' || uri.host.isEmpty) return;

    final ip = uri.host;
    _addDebugInfo('Attempting to connect to: $ip');

    try {
      WebSocket webSocket = await WebSocket.connect('ws://$ip:8080');
      String connectionId = DateTime.now().millisecondsSinceEpoch.toString();
      _connections[connectionId] = webSocket;
      _addDebugInfo('Connected to: $ip');

      setState(() {});

      webSocket.listen(
        (message) {
          _handleIncomingMessage(message, connectionId);
        },
        onError: (error) => _addDebugInfo('WebSocket error: $error'),
        onDone: () {
          _addDebugInfo('WebSocket connection closed');
          _connections.remove(connectionId);
          setState(() {});
        },
      );
    } catch (e) {
      _addDebugInfo('Failed to connect: $e');
    }
  }

  void _toggleReadyToShare() {
    setState(() {
      _isReadyToShare = !_isReadyToShare;
      _isFreeSliding = !_isReadyToShare;

      // Actualizar el viewport inicial basado en la transformación actual
      if (_isReadyToShare) {
        _updateInitialViewportFromTransform(_transformationController.value);
      }
    });
    _broadcastReadyState();

    if (_isReadyToShare) {
      _setAllDevicesReady();
    } else {
      _setAllDevicesNotReady();
    }

    _checkAllDevicesReady();
  }

  void _updateInitialViewportFromTransform(Matrix4 transform) {
    if (_uiImage == null) return;

    final Size screenSize = MediaQuery.of(context).size;
    final double scale = transform.getMaxScaleOnAxis();
    final Vector3 translation = transform.getTranslation();

    // Calcular las dimensiones del viewport visible
    double viewportWidth = screenSize.width / scale;
    double viewportHeight = screenSize.height / scale;

    // Calcular la posición del viewport
    double viewportX = -translation.x / scale;
    double viewportY = -translation.y / scale;

    // Asegurarse de que el viewport no se salga de los límites de la imagen
    viewportX =
        viewportX.clamp(0.0, _uiImage!.width.toDouble() - viewportWidth);
    viewportY =
        viewportY.clamp(0.0, _uiImage!.height.toDouble() - viewportHeight);

    setState(() {
      _initialViewport = Rect.fromLTWH(
        viewportX,
        viewportY,
        viewportWidth,
        viewportHeight,
      );
    });
  }

  void _setAllDevicesNotReady() {
    final allNotReadyMessage = {
      'type': 'set_all_ready',
      'isReady': false,
    };

    for (var connection in _connections.values) {
      connection.add(json.encode(allNotReadyMessage));
    }

    setState(() {
      _connectedDevicesReadyState.updateAll((key, value) => false);
      _isFreeSliding = true;
      _isGestureSyncEnabled =
          true; // Mantener la sincronización de gestos activa
    });
  }

  void _setAllDevicesReady() {
    final allReadyMessage = {
      'type': 'set_all_ready',
      'isReady': true,
    };

    // Broadcast the message to all connected devices
    for (var connection in _connections.values) {
      connection.add(json.encode(allReadyMessage));
    }

    // Set all local ready states to true
    setState(() {
      _connectedDevicesReadyState.updateAll((key, value) => true);
    });
  }

  void _checkAllDevicesReady() {
    bool allReady =
        _connectedDevicesReadyState.values.every((isReady) => isReady);
    setState(() {
      _allDevicesReady = allReady && _isReadyToShare;
    });
  }

  void _handleImageShared(
      String base64Image,
      String sender,
      Map<String, dynamic>? leaderViewport,
      double leaderSlideY,
      double leaderSlideX) {
    try {
      if (leaderViewport == null) {
        log('Error: leaderViewport recibido es nulo: $leaderViewport');
        return;
      }
      final Uint8List imageBytes = base64Decode(base64Image);
      ui.decodeImageFromList(imageBytes, (ui.Image result) {
        setState(() {
          _uiImage = result;
          _imageBytes = imageBytes;
          _isSharing = true;
          _hasImage = true;
          _isGestureSyncEnabled = true;
        });

        log(" $_isLeader, $_uiImage, $leaderViewport ");
        // Posiciona el viewport basado en el Leader si somos Linked
        if (!_isLeader! && _uiImage != null) {
          _positionLinkedViewport(
              Rect.fromLTWH(
                leaderViewport['left'],
                leaderViewport['top'],
                leaderViewport['width'],
                leaderViewport['height'],
              ),
              leaderSlideY,
              leaderSlideX);
        }

        print('Imagen recibida y procesada correctamente');
      });
    } catch (e) {
      print('Error al procesar la imagen recibida: $e');
    }
  }

  void _positionLinkedViewport(
      Rect leaderViewport, double leaderSlideY, double leaderSlideX) {
    // SOLO LO USA EL DISPOSITIVO LINKED
    if (_uiImage == null) {
      log('Error: _uiImage, leaderSlideY o linkedSlideY es nulo');
      return;
    }

    final screenSize = MediaQuery.of(context).size;

    // Calcula las diferencias de posición en X y Y
    double yDifference = leaderSlideY - linkedSlideY!;
    double xDifference = leaderSlideX - linkedSlideX!;

    log("leaderSlideX: $leaderSlideX & leaderSlideY: $leaderSlideY ");
    log("linkedSlideX: $linkedSlideX & linkedSlideY: $linkedSlideY ");
    log("yDifference: $yDifference ");
    log("xDifference: $xDifference ");

    final Rect linkedViewport = Rect.fromLTWH(
      leaderViewport.right + xDifference,
      leaderViewport.top + yDifference,
      leaderViewport.width,
      leaderViewport.height,
    );

    final double linkedScale = screenSize.width / leaderViewport.width;
    log("Direction: $_direction ");
    final Matrix4 linkedTransform = Matrix4.identity();
    if (_direction == 'right') {
      linkedTransform
        ..scale(linkedScale)
        ..translate(
            -(leaderViewport.left - leaderViewport.width), -linkedViewport.top);
    } else if (_direction == 'left') {
      linkedTransform
        ..scale(linkedScale)
        ..translate(-linkedViewport.left, -linkedViewport.top);
    } else if (_direction == 'up') {
      linkedTransform
        ..scale(linkedScale)
        ..translate(-leaderViewport.left,
            -(leaderViewport.top - leaderViewport.height));
    } else if (_direction == 'down') {
      linkedTransform
        ..scale(linkedScale)
        ..translate(-leaderViewport.left, -linkedViewport.bottom);
    }

    setState(() {
      _transformationController.value = linkedTransform;
      _isReadyToShare = false;
      _isFreeSliding = true;
    });

    // _notifyAfterSharing();
  }

  void _broadcastReadyState() {
    final readyStateData = {
      'type': 'ready_state',
      'isReady': _isReadyToShare,
      'hasImage': _hasImage,
    };
    for (var connection in _connections.values) {
      connection.add(json.encode(readyStateData));
    }
  }

  void _notifyAfterSharing() {
    final metadata = {
      'type': 'linked_positioned',
      'sender': user.currentUser?.email ?? 'unknown',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Notify all connected devices
    _connections.forEach((deviceId, connection) {
      try {
        connection.add(json.encode(metadata));
        print('Notification sent to device: $deviceId');
      } catch (e) {
        print('Error sending notification to device $deviceId: $e');
        _handleDisconnection(deviceId);
      }
    });

    // Update local state for all devices
    setState(() {
      _isReadyToShare = false;
      _isFreeSliding = true;

      // Reset swipe states
      _isLocalSwiping = false;
      _isSwipeInProgress = false;
      _devicesSwipingState.clear();

      // Update ready states for all devices
      _connectedDevicesReadyState.updateAll((key, value) => false);
    });

    // Check and update overall state
    _checkAllDevicesReady();
    _broadcastReadyState();
  }

  void _handleIncomingMessage(dynamic message, String connectionId) {
    Map<String, dynamic> messageData;

    try {
      if (message is String) {
        messageData = json.decode(message);
      } else if (message is Map<String, dynamic>) {
        messageData = message;
      } else {
        print('Unexpected message type: ${message.runtimeType}');
        return;
      }

      // Manejar ping/pong
      if (messageData['type'] == 'ping') {
        _connections[connectionId]?.add(json.encode({
          'type': 'pong',
          'timestamp': messageData['timestamp'],
        }));
        return;
      }

      // Evitar imprimir los mensajes 'pong'
      if (messageData['type'] != 'pong' && messageData['type'] != 'ping') {
        print("Mensaje recibido de tipo: ${messageData['type']}");
      }

      switch (messageData['type']) {
        case 'screen_size':
          _handleScreenSizeInfo(
              connectionId, messageData['width'], messageData['height']);
          break;
        case 'sync_gesture':
          if (_isGestureSyncEnabled && _isSharing) {
            final String senderId = messageData['senderId'] ?? '';

            // Si somos el Leader, reenviamos a todos los demás dispositivos
            if (_isLeader!) {
              _forwardGestureToAllDevices(messageData, senderId);
            }

            // Aplicar el gesto si no somos el emisor original
            if (senderId != user.currentUser?.email) {
              _handleSyncGesture(messageData);
            }
          }
          break;
        case 'swipe_gesture':
          _handleRemoteSwipeGesture(messageData['direction'], connectionId);
          break;
        case 'swipe_simultaneous':
          _handleSimultaneousSwipe(connectionId, messageData);
          break;
        case 'image_shared':
          final leaderViewport = messageData['leaderViewport'];
          final leaderSlideY =
              messageData['leaderSlideY']; // Obtener leaderSlideY
          final leaderSlideX =
              messageData['leaderSlideX']; // Obtener leaderSlideX

          if (leaderSlideY == null || leaderSlideX == null) {
            log('Error: leaderSlideY es nulo');
            return;
          } else {
            log('leaderSlideX: $leaderSlideX & leaderSlideY: $leaderSlideY');
          }
          _handleImageShared(
              messageData['data'],
              messageData['sender'],
              leaderViewport, // Enviar el leaderViewport como transformString
              leaderSlideY,
              leaderSlideX);
          break;
        case 'stop_sharing':
          _handleStopSharing();
          break;
        case 'set_all_ready':
          _handleSetAllReady(messageData['isReady']);
          break;
        case 'request_screen_size':
          _sendScreenSize(connectionId);
          break;
        case 'ready_state':
          _handleReadyState(
              connectionId, messageData['isReady'], messageData['hasImage']);
          break;
        case 'sharing_state_update':
          _handleSharingStateUpdate(messageData);
          break;
        default:
          print('Unknown message type: ${messageData['type']}');
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  void _handleSharingStateUpdate(Map<String, dynamic> messageData) {
    setState(() {
      _isReadyToShare = messageData['isReadyToShare'];
      _isFreeSliding = messageData['isFreeSliding'];
      _isGestureSyncEnabled = true;

      // Limpiar estados de swipe
      _devicesSwipingState.clear();
      _isLocalSwiping = false;
      _isSwipingLeft = false;
      _isSwipingRight = false;
      _isSwipingDown = false;
      _isSwipingUp = false;
    });

    // Actualizar estados relacionados
    _checkAllDevicesReady();
    _broadcastReadyState();
  }

  Rect? _getLeaderViewport() {
    if (_uiImage == null) return null;

    final transform = _transformationController.value;
    final scale = transform.getMaxScaleOnAxis();
    final translation = transform.getTranslation();
    final screenSize = MediaQuery.of(context).size;

    // Calcular las dimensiones del viewport visible
    double viewportWidth = screenSize.width / scale;
    double viewportHeight = screenSize.height / scale;

    // Calcular la posición del viewport
    double viewportX = -translation.x / scale;
    double viewportY = -translation.y / scale;

    return Rect.fromLTWH(
      viewportX,
      viewportY,
      viewportWidth,
      viewportHeight,
    );
  }

  void _forwardGestureToAllDevices(
      Map<String, dynamic> gestureData, String originalSenderId) {
    if (!_isLeader! || !_isSharing) return;

    final forwardedData = {
      ...gestureData,
      'forwarded': true,
      'originalSenderId': originalSenderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    print(
        'Leader reenviando gesto de $originalSenderId a todos los dispositivos');

    // Enviar a todos los dispositivos excepto al remitente original
    for (var entry in _connections.entries) {
      if (!forwardedData.containsKey('recipientId') ||
          forwardedData['recipientId'] == entry.key) {
        try {
          entry.value.add(json.encode(forwardedData));
        } catch (e) {
          print('Error al reenviar gesto a ${entry.key}: $e');
        }
      }
    }
  }

  void _handleSetAllReady(bool isReady) {
    setState(() {
      _isReadyToShare = isReady;
      _isFreeSliding = !isReady;
      _connectedDevicesReadyState.updateAll((key, value) => isReady);
      _isGestureSyncEnabled =
          true; // Mantener la sincronización de gestos activa
    });
    _checkAllDevicesReady();

    _broadcastReadyState();
  }

  void _handleRemoteSwipeGesture(String direction, String connectionId) {
    if (_isReadyToShare && _allDevicesReady) {
      setState(() {
        _devicesSwipingState[connectionId] = true;
        _lastSwipeTimestamps[connectionId] = DateTime.now();
        // Store the connectionId of the linked device that's swiping
        if (!_isLeader!) {
          _activeLinkedDeviceId = connectionId;
        }
      });

      Timer(swipeTimeout, () {
        setState(() {
          _devicesSwipingState[connectionId] = false;
          if (!_isLeader!) {
            _activeLinkedDeviceId = null;
          }
        });
      });

      _checkSimultaneousSwipe();
    }
  }

  void _handleSimultaneousSwipe(
      String connectionId, Map<String, dynamic> messageData) {
    bool isSwipping = messageData['isSwipping'];
    String remoteRole = messageData['role'];
    int timestamp = messageData['timestamp'];

    print('- Desde: $connectionId');
    print('- Rol: $remoteRole');
    print('- Estado: $isSwipping');
    print('- Timestamp: $timestamp');

    setState(() {
      _roleSwipeStates[remoteRole] = isSwipping;
      if (isSwipping) {
        _lastSwipeTimestamps[connectionId] =
            DateTime.fromMillisecondsSinceEpoch(timestamp);
        // Store the connectionId if it's a linked device
        if (remoteRole == 'linked') {
          _activeLinkedDeviceId = connectionId;
        }
      } else {
        _lastSwipeTimestamps.remove(connectionId);
        if (remoteRole == 'linked') {
          _activeLinkedDeviceId = null;
        }
      }
      _connectionStates[connectionId]?.isSwipping = isSwipping;
    });

    _checkSimultaneousSwipe();
  }

  void _checkSimultaneousSwipe() {
    if (_connections.isEmpty) {
      print(
          'No hay dispositivos conectados para verificar deslizamiento simultáneo');
      return;
    }

    // Actualizar el estado de swipe del rol actual
    String localRole = _isLeader! ? 'leader' : 'linked';
    _roleSwipeStates[localRole] = _isLocalSwiping;

    print('- Leader deslizando: ${_roleSwipeStates['leader']}');
    print('- Linked deslizando: ${_roleSwipeStates['linked']}');

    // Verificar que AMBOS roles estén deslizando
    bool bothRolesSwipping =
        _roleSwipeStates['leader']! && _roleSwipeStates['linked']!;

    // Verificar timestamps solo si ambos roles están deslizando
    bool swipesAreSimultaneous = false;
    if (bothRolesSwipping && _lastSwipeTimestamps.length >= 2) {
      var timestamps = _lastSwipeTimestamps.values.toList();
      var timeDifference = timestamps[0].difference(timestamps[1]).abs();
      swipesAreSimultaneous = timeDifference.inMilliseconds < 500;

      print(
          'Diferencia de tiempo entre swipes: ${timeDifference.inMilliseconds}ms');
    }

    if (bothRolesSwipping &&
        swipesAreSimultaneous &&
        _isReadyToShare &&
        _allDevicesReady &&
        _hasImage) {
      _initiateImageSharing();
    }
  }

  void _initiateImageSharing() {
    if (_hasImage && _imageBytes != null && _uiImage != null) {
      print('Compartiendo imagen...');
      // Verificar si es el dispositivo que tiene la imagen original
      if (_isLeader! && _activeLinkedDeviceId != null) {
        _shareImageWithDevice(_activeLinkedDeviceId!);
      }

      // Actualizar estados locales
      _updateSharingStates();

      // Notificar a todos los dispositivos
      _broadcastSharingStateUpdate();
    } else {
      print('No hay imagen para compartir');
    }
  }

  void _updateSharingStates() {
    setState(() {
      _isGestureSyncEnabled = true;
      _isSharing = true;
      _isReadyToShare = false;
      _isFreeSliding = true;
      _devicesSwipingState.clear();
      _isLocalSwiping = false;
      _isSwipingLeft = false;
      _isSwipingRight = false;
      _isSwipingDown = false;
      _isSwipingUp = false;
      _activeLinkedDeviceId = null;
    });
  }

  void _broadcastSharingStateUpdate() {
    final stateUpdateMessage = {
      'type': 'sharing_state_update',
      'isReadyToShare': false,
      'isFreeSliding': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _connections.forEach((deviceId, connection) {
      try {
        connection.add(json.encode(stateUpdateMessage));
        print('Estado de compartición actualizado para dispositivo: $deviceId');
      } catch (e) {
        print('Error al actualizar estado para dispositivo $deviceId: $e');
        _handleDisconnection(deviceId);
      }
    });
  }

  void _shareImageWithDevice(String deviceId) {
    if (_imageBytes != null && _uiImage != null) {
      try {
        final connection = _connections[deviceId];
        if (connection != null) {
          final base64Image = base64Encode(_imageBytes!);
          final leaderViewport = _getLeaderViewport();

          final metadata = {
            'type': 'image_shared',
            'data': base64Image,
            'sender': user.currentUser?.email ?? 'unknown',
            'leaderViewport': leaderViewport != null
                ? {
                    'left': leaderViewport.left,
                    'top': leaderViewport.top,
                    'width': leaderViewport.width,
                    'height': leaderViewport.height,
                  }
                : null,
            'leaderSlideY': leaderSlideY,
            'leaderSlideX': leaderSlideX
          };

          connection.add(json.encode(metadata));

          // Actualizar estados locales y notificar a todos
          _updateSharingStates();
          _broadcastSharingStateUpdate();
        } else {
          print('No se encontró la conexión para el dispositivo: $deviceId');
        }
      } catch (e) {
        print('Error al compartir imagen: $e');
      }
    } else {
      print('No hay imagen disponible para compartir');
    }
  }

  void _handleStopSharing() {
    setState(() {
      _isSharing = false;
    });
    print("El dispositivo remoto dejó de compartir la imagen");
  }

  void _handleReadyState(String connectionId, bool isReady, bool hasImage) {
    setState(() {
      _connectedDevicesReadyState[connectionId] = isReady;
    });
    _checkAllDevicesReady();
  }

  void _sendScreenSize(String connectionId) {
    final size = MediaQuery.of(context).size;
    final screenSizeData = {
      'type': 'screen_size',
      'width': size.width,
      'height': size.height,
    };
    _connections[connectionId]?.add(json.encode(screenSizeData));
  }

  void _handleScreenSizeInfo(String deviceId, double width, double height) {
    DeviceInfo newDevice = DeviceInfo(
      id: deviceId,
      portion: Rect.zero,
      size: Size(width, height),
    );
    connectedDevices.add(newDevice);
    myDevice ??= newDevice;
  }

  void _updateImageView() {
    if (_imageBytes != null && _uiImage != null && myDevice != null) {
      setState(() {
        // Forzar la reconstrucción del widget
      });
      print("Vista de imagen actualizada");
    } else {
      print(
          "No se puede actualizar la vista de imagen: faltan datos necesarios");
    }
  }

  void _handleSyncGesture(Map<String, dynamic> gestureData) {
    if (!_isSharing) return;

    // Evitar aplicar el gesto si somos el emisor original
    if (gestureData['senderId'] == user.currentUser?.email) {
      return;
    }

    final delta = Offset((gestureData['deltaX'] as num).toDouble(),
        (gestureData['deltaY'] as num).toDouble());
    final scale = (gestureData['scale'] as num).toDouble();
    final focalPoint = Offset((gestureData['focalPointX'] as num).toDouble(),
        (gestureData['focalPointY'] as num).toDouble());

    print('Aplicando gesto recibido de ${gestureData['senderId']}');
    _applyTransformation(delta, scale, focalPoint);
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile =
          await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        // Mantener una referencia a las conexiones actuales
        final currentConnections = Map<String, WebSocket>.from(_connections);

        final Uint8List imageBytes = await pickedFile.readAsBytes();
        final ui.Image uiImage = await _loadImage(imageBytes);

        // Verificar que las conexiones siguen activas
        if (!mounted) return;

        setState(() {
          _imageBytes = imageBytes;
          _uiImage = uiImage;
          _hasImage = true;
          _isSharing = false;
          // Restaurar las conexiones si se perdieron
          if (_connections.isEmpty) {
            _connections = currentConnections;
          }

          // Inicializar el controlador de transformación si no existe
          _transformationController = TransformationController();
        });

        _updateImageView();
        _broadcastReadyState();
        _checkAllDevicesReady();

        // Log del estado actual
        print('Estado actualizado después de cargar la imagen:');
        print('Dispositivos conectados: ${_connections.length}');
        print('Dispositivos registrados: ${connectedDevices.length}');
        print('_hasImage: $_hasImage');
        print('_imageBytes: ${_imageBytes != null}');
        print('_uiImage: ${_uiImage != null}');
        print(
            'Dimensiones de la imagen: ${_uiImage?.width}x${_uiImage?.height}');
      }
    } catch (e, stackTrace) {
      print('Error al cargar la imagen: $e');
      print('Stack trace: $stackTrace');

      // Mostrar error al usuario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar la imagen: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<ui.Image> _loadImage(Uint8List imageBytes) async {
    _verifyConnections();
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(imageBytes, (ui.Image img) {
      print("Imagen cargada: ${img.width}x${img.height}");
      completer.complete(img);
    });
    return completer.future;
  }

  void _verifyConnections() {
    _connections.forEach((id, connection) {
      try {
        // Enviar un ping para verificar la conexión
        connection.add(json.encode({
          'type': 'ping',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (e) {
        print('Conexión perdida con dispositivo $id: $e');
        _handleDisconnection(id);
      }
    });
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (_uiImage != null && _isSharing && _isGestureSyncEnabled) {
      final delta = details.focalPointDelta;
      // final scale = details.scale;
      final focalPoint = details.localFocalPoint;

      // Aplicar transformación local
      _applyTransformation(delta, 1.0, focalPoint);

      // Broadcast del gesto
      _broadcastGesture(delta, 1.0, focalPoint);
    }
  }

  void _broadcastGesture(Offset delta, double scale, Offset focalPoint) {
    if (!_isSharing) return;

    final gestureData = {
      'type': 'sync_gesture',
      'deltaX': delta.dx,
      'deltaY': delta.dy,
      'scale': scale,
      'focalPointX': focalPoint.dx,
      'focalPointY': focalPoint.dy,
      'senderId': user.currentUser?.email,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Si somos un dispositivo Linked, enviamos solo al Leader
    if (!_isLeader!) {
      print('Dispositivo Linked enviando gesto al Leader');
      for (var connection in _connections.values) {
        connection.add(json.encode(gestureData));
      }
    } else {
      // Si somos el Leader, enviamos a todos
      print('Leader enviando gesto a todos los dispositivos');
      _forwardGestureToAllDevices(
          gestureData, user.currentUser?.email ?? 'unknown');
    }
  }

  void _applyTransformation(Offset delta, double scale, Offset focalPoint) {
    if (!_isSharing) return;

    final Matrix4 currentTransform = _transformationController.value;
    final Matrix4 newTransform = Matrix4.copy(currentTransform);

    // Aplicar traslación
    newTransform.translate(delta.dx, delta.dy);

    // Aplicar escala
    // if (scale != 1.0) {
    //   final double currentScale = newTransform.getMaxScaleOnAxis();
    //   final double newScale = currentScale * scale;
    //   final double scaleChange = newScale / currentScale;

    //   final Offset focalPointDelta = focalPoint -
    //       Offset(
    //         newTransform.getTranslation().x,
    //         newTransform.getTranslation().y,
    //       );

    //   newTransform
    //     ..translate(focalPointDelta.dx, focalPointDelta.dy)
    //     ..scale(scaleChange)
    //     ..translate(-focalPointDelta.dx, -focalPointDelta.dy);
    // }

    setState(() {
      _transformationController.value = newTransform;
      if (_isReadyToShare) {
        _updateInitialViewportFromTransform(newTransform);
      }
    });
  }

  void _addDebugInfo(String info) {
    print(info);
  }

  void _onRoleSelected(bool isLeader) {
    setState(() {
      _isLeader = isLeader;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _isLeader == null
          ? ChooseroleScreen(
              isLeader:
                  _onRoleSelected, // Pasamos la función para recibir la elección
            )
          : Scaffold(
              backgroundColor: Colors.white,
              body: SafeArea(
                child: Stack(
                  children: [
                    Center(child: _buildImageView()),
                    // Solo mostramos el botón de retroceso sin AppBar
                    Positioned(
                      top: 35,
                      left: 20,
                      child: Container(
                        height: 32,
                        width: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                            icon: Icon(
                              Icons.arrow_back,
                            ),
                            onPressed: () {
                              setState(() {
                                _isLeader = null;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              floatingActionButton: (_isLeader! ||
                      (!_isLeader! && _isQRCodeScanned))
                  ? SpeedDial(
                      backgroundColor: Color(0xFF0067FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      animatedIcon: AnimatedIcons.menu_close,
                      overlayColor: Colors.black,
                      overlayOpacity: 0.5,
                      children: [
                        if (_isLeader!) ...[
                          if (_hasImage)
                            SpeedDialChild(
                              child: Icon(_isReadyToShare
                                  ? Icons.share
                                  : Icons.share_outlined),
                              label: 'Match',
                              onTap: () => _toggleReadyToShare(),
                            ),
                          if (_hasImage)
                            SpeedDialChild(
                              child: Icon(Icons.qr_code),
                              label: 'View QR',
                              onTap: () => _showQRCodeDialog(),
                            ),
                          SpeedDialChild(
                            child: Icon(Icons.add_photo_alternate),
                            label: 'Add image',
                            onTap: () => _pickImage(),
                          ),
                        ] else ...[
                          SpeedDialChild(
                            child: Icon(Icons.logout),
                            label: 'Desconectar',
                            onTap: () {
                              // Cierra conexiones
                              _connections.forEach((id, socket) {
                                try {
                                  socket.close();
                                } catch (e) {
                                  print('Error al cerrar conexión con $id: $e');
                                }
                              });

                              _connections.clear();
                              _connectedDevicesReadyState.clear();

                              // Espera un frame antes de actualizar el UI
                              Future.delayed(Duration(milliseconds: 100), () {
                                if (mounted) {
                                  setState(() {
                                    _isQRCodeScanned = false;
                                  });
                                }
                              });

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Desconectado del room"),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    )
                  : null,
            ),
    );
  }

  Widget _buildImageView() {
    // Si es líder y no hay imagen, mostrar QR
    if ((_imageBytes == null || _uiImage == null) && _isLeader!) {
      return QrCodeView();
    }

    // Si es vinculado y no ha escaneado QR, mostrar scanner
    if (!_isLeader! && !_isQRCodeScanned) {
      return Stack(
        children: [
          ShowQRView(
            onQRScanned: (String data) {
              _connectToDevice(data);
              setState(() {
                _isQRCodeScanned = true;
                _qrScanError = null; // Limpiar error si estaba
              });
            },
            onQRInvalid: (String errorMsg) {
              setState(() {
                _qrScanError = errorMsg;
                _isQRCodeScanned = false;
              });

              // Oculta el error luego de 4 segundos
              Future.delayed(Duration(seconds: 4), () {
                if (mounted) {
                  setState(() {
                    _qrScanError = null;
                  });
                }
              });
            },
          ),
          if (_qrScanError != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _qrScanError!,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      );
    }

    // Si es vinculado, ha escaneado QR pero no hay imagen y está listo para compartir
    if ((_imageBytes == null || _uiImage == null) &&
        !_isLeader! &&
        _isQRCodeScanned &&
        _isReadyToShare) {
      return GestureDetector(
        onHorizontalDragStart: _onPanDragStart,
        onHorizontalDragUpdate: _onPanDragUpdate,
        onHorizontalDragEnd: _onPanDragEnd,
        onVerticalDragStart: _onPanDragStart,
        onVerticalDragUpdate: _onPanDragUpdate,
        onVerticalDragEnd: _onPanDragEnd,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            color: Color(0xFFFFA91F).withOpacity(0.7),
          ),
          child: Stack(
            children: [
              // Contenido central
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.watch_later,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Vinculación pendiente',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Si es vinculado, ha escaneado QR pero no hay imagen y no está listo para compartir
    if ((_imageBytes == null || _uiImage == null) &&
        !_isLeader! &&
        _isQRCodeScanned) {
      return Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          color: Color(0xFF0078FF).withOpacity(0.7),
        ),
        child: Stack(
          children: [
            // Contenido central
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      color: Color(0xFF0078FF).withOpacity(0.7),
                      size: 36,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Vinculado',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Si hay imagen, construir la vista interactiva
    return LayoutBuilder(
      builder: (context, constraints) {
        // Solo aplicar gestos si la imagen existe
        if (_uiImage == null) return const SizedBox.shrink();

        // Obtener el tamaño de la pantalla
        final Size screenSize = MediaQuery.of(context).size;

        Widget imageView = InteractiveViewer(
          transformationController: _transformationController,
          boundaryMargin: EdgeInsets.all(double.infinity),
          onInteractionUpdate: _isReadyToShare ? null : _onInteractionUpdate,
          minScale: 1.0,
          maxScale: 1.0,
          scaleEnabled: false,
          panEnabled: !_isReadyToShare,
          child: CustomPaint(
            painter: ImagePainter(
              image: _uiImage!,
              initialViewport: _initialViewport,
              showHighlight: !_isFreeSliding,
              currentTransform: _transformationController.value,
              screenSize: screenSize,
            ),
            size: Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble()),
          ),
        );

        // Permitir gestos si está listo para compartir y no está en modo libre
        if (_isReadyToShare && !_isFreeSliding) {
          return GestureDetector(
            onHorizontalDragStart: _onPanDragStart,
            onHorizontalDragUpdate: _onPanDragUpdate,
            onHorizontalDragEnd: _onPanDragEnd,
            onVerticalDragStart: _onPanDragStart,
            onVerticalDragUpdate: _onPanDragUpdate,
            onVerticalDragEnd: _onPanDragEnd,
            child: imageView,
          );
        }

        return imageView;
      },
    );
  }

  // PAN
  void _onPanDragStart(DragStartDetails details) {
    if (!_isReadyToShare || _isFreeSliding) return;

    String localRole = _isLeader! ? 'leader' : 'linked';

    // Guardar el valor de Y de inicio del deslizamiento en el dispositivo Leader
    if (_isLeader!) {
      leaderSlideY = details.localPosition.dy;
      leaderSlideX = details.localPosition.dx;
    }

    setState(() {
      _startHorizontalDragX = details.localPosition.dx;
      _startVerticalDragY = details.localPosition.dy;
      _isLocalSwiping = true;
      linkedSlideY = details.localPosition.dy; // Guardar Y inicial en Linked
      linkedSlideX = details.localPosition.dx; // Guardar X inicial en Linked
      _isSwipeInProgress = true;
      _lastSwipeTimestamps['local'] = DateTime.now();
      _roleSwipeStates[localRole] = true;
    });

    _broadcastSimultaneousSwipe(true);

    // Reiniciar el temporizador de timeout
    _swipeTimeoutTimer?.cancel();
    _swipeTimeoutTimer = Timer(const Duration(milliseconds: 500), () {
      print('Timeout de deslizamiento para rol: $localRole');
      _resetSwipeState();
    });
  }

  void _onPanDragUpdate(DragUpdateDetails details) {
    if (!_isSwipeInProgress) return;

    double currentX = details.localPosition.dx;
    double dragDistanceX = currentX - _startHorizontalDragX;
    double currentY = details.localPosition.dy;
    double dragDistanceY = currentY - _startVerticalDragY;

    // Actualizar dirección del deslizamiento
    setState(() {
      _isSwipingLeft = dragDistanceX < -20;
      _isSwipingRight = dragDistanceX > 20;
      _isSwipingDown = dragDistanceY < 20;
      _isSwipingUp = dragDistanceY > -20;
      _lastSwipeTimestamps['local'] = DateTime.now();
    });

    if (_isSwipingLeft || _isSwipingRight) {
      _direction = _isSwipingLeft ? 'left' : 'right';
      _broadcastSwipeGesture(_isSwipingLeft ? 'left' : 'right');
    } else if (_isSwipingDown || _isSwipingUp) {
      _direction = _isSwipingDown ? 'down' : 'up';
      _broadcastSwipeGesture(_isSwipingDown ? 'down' : 'up');
    }

    // Resetear el temporizador de timeout
    _swipeTimeoutTimer?.cancel();
    _swipeTimeoutTimer = Timer(swipeTimeout, () {
      setState(() {
        _isLocalSwiping = false;
        _isSwipeInProgress = false;
      });
      _broadcastSimultaneousSwipe(false);
    });
  }

  void _onPanDragEnd(DragEndDetails details) {
    if (!_isReadyToShare || _isFreeSliding) return;

    print(
        'Finalizando deslizamiento en rol: ${_isLeader! ? 'leader' : 'linked'}');
    _resetSwipeState();
  }

  void _broadcastSwipeGesture(String direction) {
    final swipeData = {
      'type': 'swipe_gesture',
      'direction': direction,
    };
    for (var connection in _connections.values) {
      connection.add(json.encode(swipeData));
    }
  }

  void _resetSwipeState() {
    _swipeTimeoutTimer?.cancel();

    String localRole = _isLeader! ? 'leader' : 'linked';
    _roleSwipeStates[localRole] = false;

    setState(() {
      _isLocalSwiping = false;
      _isSwipeInProgress = false;
      _isSwipingLeft = false;
      _isSwipingRight = false;
      _isSwipingDown = false;
      _isSwipingUp = false;
      _lastSwipeTimestamps.remove('local');
      if (!_isLeader!) {
        _activeLinkedDeviceId = null;
      }
    });

    _broadcastSimultaneousSwipe(false);
  }

  void _broadcastSimultaneousSwipe(bool isSwipping) {
    if (_connections.isEmpty) {
      print('No hay dispositivos conectados para transmitir el deslizamiento');
      return;
    }

    final swipeData = {
      'type': 'swipe_simultaneous',
      'isSwipping': isSwipping,
      'role': _isLeader! ? 'leader' : 'linked',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    for (var connection in _connections.values) {
      try {
        connection.add(json.encode(swipeData));
      } catch (e) {
        print('Error al enviar estado de deslizamiento: $e');
      }
    }
  }

  // void _scanQRCode() {
  //   Navigator.of(context).push(
  //     MaterialPageRoute(
  //       builder: (context) => QRViewExample(
  //         onQRScanned: (String data) {
  //           _connectToDevice(data);
  //           setState(() {
  //             _isQRCodeScanned = true;
  //           });
  //           Navigator.of(context).pop();
  //         },
  //       ),
  //     ),
  //   );
  // }

  void _showQRCodeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 300,
              height: 300,
              child: QrCodeViewHasImage(),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _pingTimer?.cancel();
    for (var connection in _connections.values) {
      try {
        connection.close();
      } catch (e) {
        print('Error closing connection: $e');
      }
    }
    super.dispose();
  }
}

class ImagePainter extends CustomPainter {
  final ui.Image image;
  final Rect? initialViewport;
  final bool showHighlight;
  final Matrix4? currentTransform;
  final Size screenSize;

  ImagePainter({
    required this.image,
    this.initialViewport,
    this.showHighlight = true,
    this.currentTransform,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    canvas.drawImage(image, Offset.zero, paint);

    if (showHighlight && currentTransform != null) {
      final highlightPaint = Paint()
        ..color = Color(0xFFFFA91F).withOpacity(0.5)
        ..style = PaintingStyle.fill;

      // Calcular el viewport visible
      final Vector3 translation = currentTransform!.getTranslation();
      final double scale = currentTransform!.getMaxScaleOnAxis();

      // Calcular las dimensiones del viewport visible
      double viewportWidth = screenSize.width / scale;
      double viewportHeight = screenSize.height / scale;

      // Calcular la posición del viewport
      double viewportX = -translation.x / scale;
      double viewportY = -translation.y / scale;

      // Asegurarse de que el viewport no se salga de los límites de la imagen
      viewportX = viewportX.clamp(0.0, image.width.toDouble() - viewportWidth);
      viewportY =
          viewportY.clamp(0.0, image.height.toDouble() - viewportHeight);

      // Dibujar el highlight solo en el área visible
      canvas.drawRect(
        Rect.fromLTWH(
          viewportX,
          viewportY,
          viewportWidth,
          viewportHeight,
        ),
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.initialViewport != initialViewport ||
        oldDelegate.showHighlight != showHighlight ||
        oldDelegate.currentTransform != currentTransform ||
        oldDelegate.screenSize != screenSize;
  }
}

class DeviceInfo {
  final String id;
  Rect portion;
  Size size;

  DeviceInfo({required this.id, required this.portion, required this.size});
}

class ConnectionState {
  bool isConnected;
  DateTime lastActivity;
  bool isSwipping;

  ConnectionState({
    this.isConnected = false,
    DateTime? lastActivity,
    this.isSwipping = false,
  }) : lastActivity = lastActivity ?? DateTime.now();
}
