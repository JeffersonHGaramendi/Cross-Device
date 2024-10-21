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
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:crossdevice/auth/login_screen.dart';
import 'package:crossdevice/chooserole_screen.dart';
import 'package:crossdevice/qr_code_view.dart';
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

class _WifiSyncHomeState extends State<WifiSyncHome> {
  final user = FirebaseAuth.instance;
  Map<String, WebSocket> _connections = {};

  HttpServer? _server;

  Uint8List? _imageBytes;
  bool _isSharing = false;
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

  @override
  void initState() {
    super.initState();
    _startServer();
    _startPingTimer();
    _roleSwipeStates['leader'] = false;
    _roleSwipeStates['linked'] = false;
    _transformationController = TransformationController();
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
    _updateInitialViewportFromTransform(_transformationController.value);
    setState(() {
      _isReadyToShare = !_isReadyToShare;
      _isFreeSliding = !_isReadyToShare;

      // Actualizar el viewport inicial basado en la transformación actual
      // if (_isReadyToShare) {
      //   _updateInitialViewportFromTransform(_transformationController.value);
      // }
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
          _isFreeSliding =
              false; // Habilitar modo de deslizamiento libre después de compartir
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
        _isSwipingDown = false;
        _isSwipingUp = false;
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
    myDevice ??= newDevice;
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
    if (_uiImage != null && _isSharing && _isGestureSyncEnabled) {
      final delta = details.focalPointDelta;
      final scale = details.scale;
      final focalPoint = details.localFocalPoint;

      // Aplicar transformación local
      _applyTransformation(delta, scale, focalPoint);

      // Actualizar el viewport si estamos en modo Match
      if (_isReadyToShare) {
        _updateInitialViewportFromTransform(_deviceSpecificTransform);
      }

      // Broadcast del gesto
      _broadcastGesture(delta, scale, focalPoint);
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
              body: Center(child: _buildImageView()),
              floatingActionButton: _isLeader!
                  ? SpeedDial(
                      animatedIcon: AnimatedIcons.menu_close,
                      overlayColor: Colors.black,
                      overlayOpacity: 0.5,
                      children: [
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanQRCode();
      });
      return const Center(child: CircularProgressIndicator());
    }

    // Si es vinculado, ha escaneado QR pero no hay imagen
    if ((_imageBytes == null || _uiImage == null) &&
        !_isLeader! &&
        _isQRCodeScanned) {
      // print(
      //     'Mostrando mensaje de espera...');
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

        // Obtener el tamaño de la pantalla
        final Size screenSize = MediaQuery.of(context).size;

        Widget imageView = InteractiveViewer(
          transformationController: _transformationController,
          boundaryMargin: EdgeInsets.all(double.infinity),
          onInteractionUpdate: _isReadyToShare ? null : _onInteractionUpdate,
          maxScale: 1.5,
          scaleEnabled: !_isReadyToShare,
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

  // HORIZONTAL
  void _onPanDragStart(DragStartDetails details) {
    if (!_isReadyToShare || _isFreeSliding) return;

    String localRole = _isLeader! ? 'leader' : 'linked';
    print('\nIniciando deslizamiento:');
    print('- Rol: $localRole');

    setState(() {
      _startHorizontalDragX = details.localPosition.dx;
      _startVerticalDragY = details.localPosition.dy;
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
      _isSwipingDown = dragDistanceY < -20;
      _isSwipingUp = dragDistanceY > 20;
      _lastSwipeTimestamps['local'] = DateTime.now();
    });

    if (_isSwipingLeft || _isSwipingRight) {
      _broadcastSwipeGesture(_isSwipingLeft ? 'left' : 'right');
      _checkSimultaneousSwipe();
    } else if (_isSwipingDown || _isSwipingUp) {
      _broadcastSwipeGesture(_isSwipingDown ? 'down' : 'up');
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

    print('Enviando estado de deslizamiento: $swipeData');

    for (var connection in _connections.values) {
      try {
        connection.add(json.encode(swipeData));
      } catch (e) {
        print('Error al enviar estado de deslizamiento: $e');
      }
    }
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

  void _showQRCodeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            width: 300,
            height: 300,
            child: QrCodeView(),
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
        ..color = Colors.yellow.withOpacity(0.3)
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
  }) : this.lastActivity = lastActivity ?? DateTime.now();
}
