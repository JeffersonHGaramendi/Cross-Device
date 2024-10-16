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
import 'dart:math' as math;

import 'package:crossdevice/auth/login_screen.dart';
import 'package:crossdevice/chooserole_screen.dart';
import 'package:crossdevice/navbar.dart';
import 'package:crossdevice/scan_qr.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:convert';
import 'dart:io';

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
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: LoginScreen(),
      //home: WifiSyncHome(),
    );
  }
}

class WifiSyncHome extends StatefulWidget {
  @override
  _WifiSyncHomeState createState() => _WifiSyncHomeState();
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
  }) : this.lastActivity = lastActivity ?? DateTime.now();
}

class _WifiSyncHomeState extends State<WifiSyncHome> {
  final NetworkInfo _networkInfo = NetworkInfo();
  final user = FirebaseAuth.instance;
  Map<String, WebSocket> _connections = {};

  bool _isServerRunning = false;
  String _localIp = '';
  String _debugInfo = '';
  HttpServer? _server;

  Uint8List? _imageBytes;
  bool _isSharing = false;
  TransformationController _transformationController =
      TransformationController();
  ui.Image? _uiImage;

  Rect? _initialViewport;

  List<DeviceInfo> connectedDevices = [];
  DeviceInfo? myDevice;

  Matrix4 _deviceSpecificTransform = Matrix4.identity();

  bool _isReadyToShare = false;
  bool _hasImage = false;
  Map<String, bool> _connectedDevicesReadyState = {};

  bool _allDevicesReady = false;
  double _startHorizontalDragX = 0;
  bool _isSwipingLeft = false;
  bool _isSwipingRight = false;

  bool _isFreeSliding = true;

  bool _isGestureSyncEnabled = false;

  bool? _isLeader;
  bool _isQRCodeScanned = false;

  bool _isImageDraggingEnabled = true;

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

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _getLocalIp();
    _startServer();
    _startPingTimer();
    _roleSwipeStates['leader'] = false;
    _roleSwipeStates['linked'] = false;
    //_initializeLocalDevice();
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
      setState(() {
        _isServerRunning = true;
      });
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
    Map<String, dynamic> connectionInfo = json.decode(data);
    String ip = connectionInfo['ip'];
    _addDebugInfo('Attempting to connect to: $ip');
    try {
      WebSocket webSocket = await WebSocket.connect('ws://$ip:8080');
      String connectionId = DateTime.now().millisecondsSinceEpoch.toString();
      _connections[connectionId] = webSocket;
      _addDebugInfo('Connected to: $ip');
      setState(() {});
      webSocket.listen(
        (message) {
          // _addDebugInfo('Received message: $message');
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
      _isImageDraggingEnabled = true; // Siempre permitir el arrastre de imagen
    });
    _broadcastReadyState();

    if (_isReadyToShare) {
      _setAllDevicesReady();
    } else {
      _setAllDevicesNotReady();
    }

    _checkAllDevicesReady();
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

  void _broadcastImageMetadata() {
    if (_imageBytes != null && _uiImage != null) {
      try {
        final base64Image = base64Encode(_imageBytes!);
        final metadata = {
          'type': 'image_shared',
          'data': base64Image,
          'sender': user.currentUser?.email ?? 'unknown',
          'transform': _deviceSpecificTransform.storage.toList().toString(),
        };

        print('Enviando imagen a ${_connections.length} dispositivos');
        for (var connection in _connections.values) {
          connection.add(json.encode(metadata));
          print('Imagen enviada a dispositivo');
        }

        setState(() {
          _isSharing = true;
          _isGestureSyncEnabled = true;
          _hasImage = true;
          // _isFreeSliding =
          //     true; // Habilitar modo de deslizamiento libre después de compartir
        });
      } catch (e) {
        print('Error al compartir imagen: $e');
      }
    } else {
      print('No hay imagen disponible para compartir');
    }
  }

  void _handleImageShared(
      String base64Image, String sender, String? transformString) {
    try {
      final Uint8List imageBytes = base64Decode(base64Image);
      ui.decodeImageFromList(imageBytes, (ui.Image result) {
        setState(() {
          _uiImage = result;
          _imageBytes = imageBytes;
          _isSharing = true;
          _hasImage = true;
          _isGestureSyncEnabled = true;
        });

        if (transformString != null) {
          _applyReceivedTransform(transformString);
        }

        _calculateImagePortions();
        _updateImageView();

        print('Imagen recibida y procesada correctamente');
      });
    } catch (e) {
      print('Error al procesar la imagen recibida: $e');
    }
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
      if (messageData['type'] != 'pong') {
        print("Mensaje recibido de tipo: ${messageData['type']}");
      }

      switch (messageData['type']) {
        case 'screen_size':
          _handleScreenSizeInfo(
              connectionId, messageData['width'], messageData['height']);
          break;
        case 'image_metadata':
          _handleReceivedImage(messageData['data'], messageData['sender'],
              messageData['transform']);
          break;
        case 'image_portion':
          _handleReceivedImagePortion(
              messageData['deviceId'], messageData['portion']);
          break;
        case 'sync_gesture':
          if (_isGestureSyncEnabled) {
            _handleSyncGesture(messageData);
          }
          break;
        case 'swipe_gesture':
          _handleRemoteSwipeGesture(messageData['direction'], connectionId);
          break;
        case 'swipe_simultaneous':
          _handleSimultaneousSwipe(connectionId, messageData);
          break;
        case 'image_shared':
          _handleImageShared(messageData['data'], messageData['sender'],
              messageData['transform']);
          break;
        case 'stop_sharing':
          _handleStopSharing();
          break;
        case 'image_request':
          if (_hasImage && _isReadyToShare) {
            _broadcastImageMetadata();
          }
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
        default:
          print('Unknown message type: ${messageData['type']}');
      }
    } catch (e) {
      print('Error handling message: $e');
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

    print('Recibido estado de deslizamiento:');
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

    print('\nVerificando deslizamiento simultáneo:');
    print('Estado de roles:');
    print('- Leader deslizando: ${_roleSwipeStates['leader']}');
    print('- Linked deslizando: ${_roleSwipeStates['linked']}');
    print('- Rol local ($localRole) deslizando: $_isLocalSwiping');

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

    print('\nResultado de la verificación:');
    print('- Ambos roles deslizando: $bothRolesSwipping');
    print('- Deslizamientos simultáneos: $swipesAreSimultaneous');
    print('- Listo para compartir: $_isReadyToShare');
    print('- Todos dispositivos listos: $_allDevicesReady');
    print('- Tiene imagen: $_hasImage');

    if (bothRolesSwipping &&
        swipesAreSimultaneous &&
        _isReadyToShare &&
        _allDevicesReady &&
        _hasImage) {
      print('\n¡DESLIZAMIENTO SIMULTÁNEO DETECTADO! - Iniciando compartir');
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

      setState(() {
        _isGestureSyncEnabled = true;
        _isSharing = true;
        _devicesSwipingState.clear();
        _isLocalSwiping = false;
        _isSwipingLeft = false;
        _isSwipingRight = false;
        _activeLinkedDeviceId = null; // Reset the active device
      });
    } else {
      print('No hay imagen para compartir');
    }
  }

  void _shareImageWithDevice(String deviceId) {
    if (_imageBytes != null && _uiImage != null) {
      try {
        final connection = _connections[deviceId];
        if (connection != null) {
          final base64Image = base64Encode(_imageBytes!);
          final metadata = {
            'type': 'image_shared',
            'data': base64Image,
            'sender': user.currentUser?.email ?? 'unknown',
            'transform': _deviceSpecificTransform.storage.toList().toString(),
          };

          print('Enviando imagen al dispositivo: $deviceId');
          connection.add(json.encode(metadata));
          print('Imagen enviada al dispositivo');

          setState(() {
            _isSharing = true;
            _isGestureSyncEnabled = true;
            _hasImage = true;
          });
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
    if (myDevice == null) {
      myDevice = newDevice;
    }
    _calculateImagePortions();
  }

  void _calculateImagePortions() {
    if (_uiImage == null || connectedDevices.isEmpty) return;

    double totalWidth =
        connectedDevices.fold(0.0, (sum, device) => sum + device.size.width);
    double maxHeight =
        connectedDevices.map((d) => d.size.height).reduce(math.max);

    double scaleFactorWidth = _uiImage!.width / totalWidth;
    double scaleFactorHeight = _uiImage!.height / maxHeight;
    double scaleFactor = math.min(scaleFactorWidth, scaleFactorHeight);

    double currentX = 0.0;
    for (var device in connectedDevices) {
      double portionWidth = device.size.width * scaleFactor;
      double portionHeight = device.size.height * scaleFactor;

      device.portion = Rect.fromLTWH(
        currentX / _uiImage!.width,
        0,
        portionWidth / _uiImage!.width,
        portionHeight / _uiImage!.height,
      );

      currentX += portionWidth;

      if (device.id == myDevice?.id) {
        setState(() {
          myDevice = device;
          _initialViewport = device.portion;
          _setInitialTransform();
        });
      }
    }

    _broadcastImagePortions();
    setState(() {});
    _setInitialTransform();
  }

  void _setInitialTransform() {
    if (_initialViewport != null && _uiImage != null) {
      final viewportWidth = _initialViewport!.width * _uiImage!.width;
      final viewportHeight = _initialViewport!.height * _uiImage!.height;
      final scale = math.min(
        MediaQuery.of(context).size.width / viewportWidth,
        MediaQuery.of(context).size.height / viewportHeight,
      );

      _deviceSpecificTransform = Matrix4.identity()
        ..translate(
          -_initialViewport!.left * _uiImage!.width * scale,
          -_initialViewport!.top * _uiImage!.height * scale,
        )
        ..scale(scale);

      setState(() {});
    }
  }

  void _broadcastImagePortions() {
    for (var device in connectedDevices) {
      final portionData = {
        'type': 'image_portion',
        'deviceId': device.id,
        'portion': {
          'left': device.portion.left,
          'top': device.portion.top,
          'width': device.portion.width,
          'height': device.portion.height,
        },
      };
      _connections[device.id]?.add(json.encode(portionData));
    }
  }

  void _handleReceivedImage(
      String base64Image, String sender, String? transformString) {
    final Uint8List imageBytes = base64Decode(base64Image);
    ui.decodeImageFromList(imageBytes, (ui.Image result) {
      setState(() {
        _uiImage = result;
        _imageBytes = imageBytes;
        _isSharing = false;
        _hasImage = true;
        _isReadyToShare = false;
      });
      if (transformString != null) {
        _applyReceivedTransform(transformString);
      }
      _calculateImagePortions();
      _updateImageView();
    });
  }

  void _applyReceivedTransform(String transformString) {
    try {
      List<double> transformValues = transformString
          .split(',')
          .map((s) => double.parse(s.trim()))
          .toList();
      _deviceSpecificTransform = Matrix4.fromList(transformValues);
    } catch (e) {
      print('Error applying received transform: $e');
      _deviceSpecificTransform = Matrix4.identity();
    }
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

  void _handleReceivedImagePortion(
      String deviceId, Map<String, dynamic> portionData) {
    if (deviceId == myDevice?.id) {
      setState(() {
        myDevice?.portion = Rect.fromLTWH(
          portionData['left'],
          portionData['top'],
          portionData['width'],
          portionData['height'],
        );
      });
      print(
          "Porción de imagen actualizada para mi dispositivo: ${myDevice?.portion}");
      _updateImageView();
    }
  }

  void _handleSyncGesture(Map<String, dynamic> gestureData) {
    final delta = Offset(gestureData['deltaX'], gestureData['deltaY']);
    final scale = gestureData['scale'];
    final focalPoint =
        Offset(gestureData['focalPointX'], gestureData['focalPointY']);

    // Aplicar la transformación sin importar el estado de deslizamiento libre
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
        });

        // Esperar a que el estado se actualice
        await Future.delayed(const Duration(milliseconds: 200));

        // Verificar y recalcular las porciones de imagen solo si hay dispositivos conectados
        if (connectedDevices.isNotEmpty) {
          _calculateImagePortions();
        } else {
          // Si no hay dispositivos conectados, reinicializar el dispositivo local
          _initializeLocalDevice();
        }

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
    if (_uiImage != null) {
      final delta = details.focalPointDelta;
      final scale = details.scale;
      final focalPoint = details.localFocalPoint;

      _applyTransformation(delta, scale, focalPoint);

      // Siempre sincronizar gestos, independientemente del estado de deslizamiento libre
      _broadcastGesture(delta, scale, focalPoint);
    }
  }

  void _broadcastGesture(Offset delta, double scale, Offset focalPoint) {
    final gestureData = {
      'type': 'sync_gesture',
      'deltaX': delta.dx,
      'deltaY': delta.dy,
      'scale': scale,
      'focalPointX': focalPoint.dx,
      'focalPointY': focalPoint.dy,
    };

    for (var connection in _connections.values) {
      connection.add(json.encode(gestureData));
    }
  }

  void _applyTransformation(Offset delta, double scale, Offset focalPoint) {
    final Matrix4 newTransform = Matrix4.copy(_deviceSpecificTransform);

    // Aplicar traslación
    newTransform.translate(delta.dx, delta.dy);

    // Aplicar escala
    if (scale != 1.0) {
      final double currentScale = newTransform.getMaxScaleOnAxis();
      final double newScale = currentScale * scale;
      final double scaleChange = newScale / currentScale;

      final Offset focalPointDelta = focalPoint -
          Offset(
            newTransform.getTranslation().x,
            newTransform.getTranslation().y,
          );

      newTransform
        ..translate(focalPointDelta.dx, focalPointDelta.dy)
        ..scale(scaleChange)
        ..translate(-focalPointDelta.dx, -focalPointDelta.dy);
    }

    setState(() {
      _deviceSpecificTransform = newTransform;
    });
  }

  void _addDebugInfo(String info) {
    setState(() {
      _debugInfo += '$info\n';
    });
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
              appBar: AppBar(
                  title: Text('Cross Device'),
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() {
                        _isLeader = null; // Regresar a la pantalla de selección
                      });
                    },
                  )),
              body: Center(
                  child: _isLeader! ? _buildImageView() : _buildImageView()),
              floatingActionButton: _isLeader!
                  ? SpeedDial(
                      animatedIcon: AnimatedIcons.menu_close,
                      overlayColor: Colors.black,
                      overlayOpacity: 0.5,
                      children: [
                        SpeedDialChild(
                          child: Icon(_isReadyToShare
                              ? Icons.share
                              : Icons.share_outlined),
                          label: 'Match',
                          onTap: () => _toggleReadyToShare(),
                        ),
                        SpeedDialChild(
                          child: Icon(Icons.add_photo_alternate),
                          label: 'Add image',
                          onTap: () => _pickImage(),
                        ),
                      ],
                    )
                  : null,
            ),
    );
  }

  Widget _buildImageView() {
    // Si es líder y no hay imagen, mostrar QR
    if ((_imageBytes == null || _uiImage == null) && _isLeader!) {
      return _buildQRCodeView();
    }

    // Si es vinculado y no ha escaneado QR, mostrar scanner
    if (!_isLeader! && !_isQRCodeScanned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanQRCode();
      });
      return const Center(child: CircularProgressIndicator());
    }

    // Si es vinculado, ha escaneado QR pero no hay imagen, mostrar espera
    if ((_imageBytes == null || _uiImage == null) &&
        !_isLeader! &&
        _isQRCodeScanned) {
      // print(
      //     'Mostrando mensaje de espera...');
      return GestureDetector(
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          color: Colors.transparent,
          child: const Center(child: Text('Esperando una imagen...')),
        ),
      );
    }

    // Si hay imagen, construir la vista interactiva
    return LayoutBuilder(
      builder: (context, constraints) {
        // Solo aplicar gestos si la imagen existe
        if (_uiImage == null) return const SizedBox.shrink();

        Widget imageView = InteractiveViewer(
          transformationController:
              TransformationController(_deviceSpecificTransform),
          onInteractionUpdate: _onInteractionUpdate,
          maxScale: 10.0,
          child: CustomPaint(
            painter: ImagePainter(
              image: _uiImage!,
              initialViewport: _initialViewport,
              showHighlight: !_isFreeSliding,
            ),
            size: Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble()),
          ),
        );

        // Permitir gestos si está listo para compartir y no está en modo libre
        if (_isReadyToShare && !_isFreeSliding) {
          return GestureDetector(
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: imageView,
          );
        }

        return imageView;
      },
    );
  }

  // HORIZONTAL
  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_isReadyToShare || _isFreeSliding) return;

    String localRole = _isLeader! ? 'leader' : 'linked';
    print('\nIniciando deslizamiento horizontal:');
    print('- Rol: $localRole');

    setState(() {
      _startHorizontalDragX = details.localPosition.dx;
      _isLocalSwiping = true;
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

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isSwipeInProgress) return;

    double currentX = details.localPosition.dx;
    double dragDistance = currentX - _startHorizontalDragX;

    // Actualizar dirección del deslizamiento
    setState(() {
      _isSwipingLeft = dragDistance < -20;
      _isSwipingRight = dragDistance > 20;
      _lastSwipeTimestamps['local'] = DateTime.now();
    });

    if (_isSwipingLeft || _isSwipingRight) {
      _broadcastSwipeGesture(_isSwipingLeft ? 'left' : 'right');
      _checkSimultaneousSwipe();
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

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isReadyToShare || _isFreeSliding) return;

    print(
        'Finalizando deslizamiento horizontal en rol: ${_isLeader! ? 'leader' : 'linked'}');
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

    print('Enviando estado de deslizamiento: $swipeData');

    for (var connection in _connections.values) {
      try {
        connection.add(json.encode(swipeData));
      } catch (e) {
        print('Error al enviar estado de deslizamiento: $e');
      }
    }
  }

  Widget _buildQRCodeView() {
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 300,
          maxHeight: 300,
        ),
        child: SizedBox(
          width: 250,
          height: 250,
          child: QrImageView(
            data: json.encode({
              'ip': _localIp
            }), // Aquí puedes pasar el dato que desees mostrar en el QR
            version: QrVersions.auto,
            size: 250.0,
          ),
        ),
      ),
    );
  }

  void _scanQRCode() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QRViewExample(
          onQRScanned: (String data) {
            _connectToDevice(data);
            setState(() {
              _isQRCodeScanned = true;
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
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

  ImagePainter({
    required this.image,
    this.initialViewport,
    this.showHighlight = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    canvas.drawImage(image, Offset.zero, paint);

    if (showHighlight && initialViewport != null) {
      final highlightPaint = Paint()
        ..color = Colors.yellow.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(
          initialViewport!.left * image.width,
          initialViewport!.top * image.height,
          initialViewport!.width * image.width,
          initialViewport!.height * image.height,
        ),
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.initialViewport != initialViewport ||
        oldDelegate.showHighlight != showHighlight;
  }
}
