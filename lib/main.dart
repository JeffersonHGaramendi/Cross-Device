import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import 'package:crossdevice/auth/login_screen.dart';
import 'package:crossdevice/chooserole_screen.dart';
import 'package:crossdevice/qr_code_view.dart';
import 'package:crossdevice/qr_code_view_has_image.dart';
import 'package:crossdevice/scan_qr.dart';
import 'package:crossdevice/utils/chunked_image_loader.dart';
import 'package:crossdevice/widgets/loading_overlay.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
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

  Timer? _swipeTimeoutTimer;
  static const swipeTimeout = Duration(milliseconds: 1000);

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

  double? leaderScale;

  String? _qrScanError;

  bool _awaitingLinkedSwipe = false;
  Timer? _syncWindowTimer;
  static const Duration syncWindowDuration = Duration(milliseconds: 750);

  bool _isLoadingImage = false;
  double _loadProgress = 0.0;

  bool _isReceivingImage = false;
  double _receiveProgress = 0.0;

  StringBuffer? _imageChunkBuffer;

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
      double leaderSlideX,
      double leaderScale) {
    try {
      if (leaderViewport == null) {
        log('Error: leaderViewport recibido es nulo: $leaderViewport');
        return;
      }
      final Uint8List imageBytes = base64Decode(base64Image);
      ui.decodeImageFromList(imageBytes, (ui.Image result) {
        // 🔧 Primero aplicar transformación (sin disparar render aún)
        if (!_isLeader!) {
          _uiImage = result;
          _positionLinkedViewport(
            Rect.fromLTWH(
              leaderViewport['left'],
              leaderViewport['top'],
              leaderViewport['width'],
              leaderViewport['height'],
            ),
            leaderSlideY,
            leaderSlideX,
            leaderScale,
          );
        }

        setState(() {
          _uiImage = result;
          _imageBytes = imageBytes;
          _isSharing = true;
          _hasImage = true;
          _isGestureSyncEnabled = true;
        });

        print('Imagen recibida y posicionada correctamente');
      });
    } catch (e) {
      print('Error al procesar la imagen recibida: $e');
    }
  }

  Future<ui.Image> _decodeImageFromBytes(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }

  void _positionLinkedViewport(
    Rect leaderViewport,
    double leaderSlideY,
    double leaderSlideX,
    double leaderScale,
  ) {
    if (_uiImage == null || linkedSlideY == null || linkedSlideX == null) {
      log('❌ Datos insuficientes para calcular el viewport');
      return;
    }

    final Size linkedScreenSize = MediaQuery.of(context).size;
    final double scale = leaderScale;

    final double linkedWidthInImage = linkedScreenSize.width / scale;
    final double linkedHeightInImage = linkedScreenSize.height / scale;

    // Por defecto: comenzar desde la misma posición
    double newX = leaderViewport.left;
    double newY = leaderViewport.top;

    // ➡️ Linked se posiciona a la izquierda del Leader
    if (_direction == 'right') {
      newX = leaderViewport.left - linkedWidthInImage;
      newY = leaderViewport.top + (leaderSlideY - linkedSlideY!);
    }

    // ⬅️ Linked se posiciona a la derecha del Leader
    else if (_direction == 'left') {
      newX = leaderViewport.right;
      newY = leaderViewport.top + (leaderSlideY - linkedSlideY!);
    }

    // ⬆️ Linked se posiciona debajo del Leader
    else if (_direction == 'up') {
      newY = leaderViewport.bottom;
      newX = leaderViewport.left + (leaderSlideX - linkedSlideX!);
    }

    // ⬇️ Linked se posiciona encima del Leader
    else if (_direction == 'down') {
      newY = leaderViewport.top - linkedHeightInImage;
      newX = leaderViewport.left + (leaderSlideX - linkedSlideX!);
    } else {
      print("❌ Dirección desconocida: $_direction");
      return;
    }

    final Matrix4 linkedTransform = Matrix4.identity()
      ..scale(scale)
      ..translate(-newX, -newY);

    log("📥 Swipe ($_direction):");
    log("  LeaderViewport: $leaderViewport");
    log("  newX: $newX, newY: $newY");
    log("  linked width in image: $linkedWidthInImage");
    log("  linked height in image: $linkedHeightInImage");

    setState(() {
      _transformationController.value = linkedTransform;
      _isReadyToShare = false;
      _isFreeSliding = true;
    });

    log("✅ Viewport reposicionado en Linked.");
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

  Future<void> _handleIncomingMessage(
      dynamic message, String connectionId) async {
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
        case 'image_chunk':
          final String chunk = messageData['chunk'] ?? '';
          final bool isLast = messageData['isLast'] ?? false;

          // Acumulador local (debes crearlo a nivel de clase)
          _imageChunkBuffer ??= StringBuffer();
          _imageChunkBuffer!.write(chunk);

          setState(() {
            _receiveProgress = (_imageChunkBuffer!.length / (15 * 1024 * 1024))
                .clamp(0.0, 0.99); // Asume máximo 15MB base64
            _isReceivingImage = true;
          });

          if (isLast) {
            final completeBase64 = _imageChunkBuffer.toString();
            _imageChunkBuffer = null;

            final Uint8List imageBytes = base64Decode(completeBase64);
            _imageBytes = imageBytes;

            final decodedImage = await _decodeImageFromBytes(imageBytes);
            setState(() {
              _uiImage = decodedImage;
              _isReceivingImage = false;
              _receiveProgress = 0.0;
            });

            _handleImageShared(
              completeBase64,
              messageData['sender'],
              messageData['leaderViewport'],
              messageData['leaderSlideY'],
              messageData['leaderSlideX'],
              messageData['leaderScale'],
            );
          }
          break;
        case 'relative_gesture':
          if (_isSharing && _uiImage != null) {
            final senderId = messageData['senderId'];
            if (senderId == myDevice?.id) return;

            final double dxPercent =
                (messageData['normalizedDeltaX'] as num).toDouble();
            final double dyPercent =
                (messageData['normalizedDeltaY'] as num).toDouble();

            final Rect? localViewport = _getLeaderViewport();
            if (localViewport == null) return;

            final double dx = double.parse(
                (dxPercent * localViewport.width).toStringAsFixed(5));
            final double dy = double.parse(
                (dyPercent * localViewport.height).toStringAsFixed(5));

            final Matrix4 newTransform =
                Matrix4.copy(_transformationController.value)
                  ..translate(dx, dy);

            setState(() {
              _transformationController.value = newTransform;
            });

            print('📥 Gesto relativo aplicado: dx=$dx, dy=$dy');

            // ✅ REENVIAR A OTROS DISPOSITIVOS (si soy Leader)
            if (_isLeader! && senderId != myDevice?.id) {
              final forwardedData = {
                ...messageData,
                'type': 'relative_gesture',
                'senderId': senderId,
                'forwarded': true,
              };

              for (var entry in _connections.entries) {
                if (entry.key != senderId) {
                  try {
                    entry.value.add(json.encode(forwardedData));
                  } catch (e) {
                    print('Error reenviando gesto a ${entry.key}: $e');
                  }
                }
              }
            }
          }
          break;
        case 'stop_session':
          _resetSession();
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

    final Matrix4 transform = _transformationController.value;
    final double scale = transform.getMaxScaleOnAxis();
    final Vector3 translation = transform.getTranslation();
    final Size screenSize = MediaQuery.of(context).size;

    double viewportWidth = screenSize.width / scale;
    double viewportHeight = screenSize.height / scale;
    double viewportX = -translation.x / scale;
    double viewportY = -translation.y / scale;

    leaderScale = scale;

    return Rect.fromLTWH(viewportX, viewportY, viewportWidth, viewportHeight);
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
      if (entry.key != originalSenderId) {
        print('🔁 Reenviando gesto de $originalSenderId a ${entry.key}');
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
    }
  }

  void _handleSimultaneousSwipe(
      String connectionId, Map<String, dynamic> messageData) {
    bool isSwipping = messageData['isSwipping'];
    String remoteRole = messageData['role'];

    print('- Desde: $connectionId');
    print('- Rol: $remoteRole');
    print('- Estado: $isSwipping');

    setState(() {
      _roleSwipeStates[remoteRole] = isSwipping;
      _connectionStates[connectionId]?.isSwipping = isSwipping;

      if (isSwipping && remoteRole == 'linked') {
        _activeLinkedDeviceId = connectionId;
        // Leer coordenadas del Linked desde el mensaje recibido
        if (messageData.containsKey('linkedSlideX') &&
            messageData.containsKey('linkedSlideY')) {
          linkedSlideX = (messageData['linkedSlideX'] as num?)?.toDouble();
          linkedSlideY = (messageData['linkedSlideY'] as num?)?.toDouble();
        }
      }
      if (!isSwipping && remoteRole == 'linked') {
        _activeLinkedDeviceId = null;
      }
    });

    if (_isLeader! && _isReadyToShare && _allDevicesReady) {
      if (remoteRole == 'linked' && isSwipping && _awaitingLinkedSwipe) {
        // Validar que los gestos sean opuestos
        final double? xDiff = leaderSlideX != null && linkedSlideX != null
            ? leaderSlideX! - linkedSlideX!
            : null;
        final double? yDiff = leaderSlideY != null && linkedSlideY != null
            ? leaderSlideY! - linkedSlideY!
            : null;

        print('🧪 Validando gesto opuesto...');
        print('➡️ Dirección Leader: $_direction');
        print('leaderSlideX: $leaderSlideX / linkedSlideX: $linkedSlideX');
        print('leaderSlideY: $leaderSlideY / linkedSlideY: $linkedSlideY');
        print('xDiff: $xDiff');
        print('yDiff: $yDiff');

        final bool oppositeX =
            (_direction == 'left' && xDiff != null && xDiff < 0) ||
                (_direction == 'right' && xDiff != null && xDiff > 0);
        final bool oppositeY =
            (_direction == 'up' && yDiff != null && yDiff < 0) ||
                (_direction == 'down' && yDiff != null && yDiff > 0);

        final bool isOpposite = oppositeX || oppositeY;
        print('✅ ¿Son opuestos? $isOpposite');

        if (isOpposite) {
          print('🎯 Gesto válido: compartiendo imagen');
          _initiateImageSharing();
          _awaitingLinkedSwipe = false;
          _syncWindowTimer?.cancel();
        } else {
          print('❌ Gestos no opuestos: no se comparte imagen');
        }
      }
    }
  }

  void _initiateImageSharing() {
    print('📡 Compartiendo imagen...');
    print('🔢 Tamaño: ${_imageBytes?.length}');
    if (_imageBytes == null || _imageBytes!.isEmpty) {
      print('❌ No hay imagen cargada para compartir.');
      return;
    }
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

  void _shareImageWithDevice(String deviceId) async {
    if (_imageBytes == null || _uiImage == null) {
      print('❌ No hay imagen cargada para compartir.');
      return;
    }

    final connection = _connections[deviceId];
    if (connection == null) {
      print('❌ No se encontró conexión para el dispositivo $deviceId');
      return;
    }

    final String base64Image = base64Encode(_imageBytes!);
    const int chunkSize = 64 * 1024;
    int offset = 0;

    // Metadata para la imagen (solo en el primer chunk)
    final leaderViewport = _getLeaderViewport();
    if (leaderViewport == null) {
      print('❌ No se pudo obtener el viewport del Leader');
      return;
    }

    if (leaderSlideX == null || leaderSlideY == null || leaderScale == null) {
      print('❌ Coordenadas del swipe o escala nulas.');
      return;
    }

    final metadata = {
      'type': 'image_chunk',
      'leaderViewport': {
        'left': leaderViewport.left,
        'top': leaderViewport.top,
        'width': leaderViewport.width,
        'height': leaderViewport.height,
      },
      'leaderSlideX': leaderSlideX,
      'leaderSlideY': leaderSlideY,
      'leaderScale': leaderScale,
      'sender': user.currentUser?.email ?? 'unknown',
    };

    // 🔁 Envío por partes
    while (offset < base64Image.length) {
      final end = (offset + chunkSize).clamp(0, base64Image.length);
      final chunk = base64Image.substring(offset, end);

      final message = {
        ...metadata,
        'type': 'image_chunk',
        'chunk': chunk,
        'isLast': end == base64Image.length,
      };

      try {
        connection.add(json.encode(message));
      } catch (e) {
        print('❌ Error al enviar chunk: $e');
        _handleDisconnection(deviceId);
        return;
      }

      offset = end;
      await Future.delayed(const Duration(milliseconds: 5));
    }

    _updateSharingStates();
    _broadcastSharingStateUpdate();
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
    if (!_isSharing || _uiImage == null) return;

    final senderId = gestureData['senderId'];
    final originalSenderId = gestureData['originalSenderId'];

    if (originalSenderId != null && originalSenderId == myDevice?.id) return;

    final double remoteDeltaX = (gestureData['deltaX'] as num).toDouble();
    final double remoteDeltaY = (gestureData['deltaY'] as num).toDouble();
    final double remoteScale = (gestureData['scale'] as num).toDouble();

    final double localScale =
        _transformationController.value.getMaxScaleOnAxis();

    final Size localSize = MediaQuery.of(context).size;
    final double remoteWidth =
        (gestureData['screenWidth'] as num?)?.toDouble() ?? localSize.width;
    final double remoteHeight =
        (gestureData['screenHeight'] as num?)?.toDouble() ?? localSize.height;

    // ✅ Calcular delta como proporción relativa de la pantalla remota
    final double normalizedDeltaX = remoteDeltaX / remoteWidth;
    final double normalizedDeltaY = remoteDeltaY / remoteHeight;

    // ✅ Aplicar proporcionalmente a la pantalla local y ajustar por escala
    final Rect? localViewport = _getLeaderViewport();
    if (localViewport == null) return;

    // Aplicar el delta en proporción al viewport local
    final Offset scaledDelta = Offset(
      normalizedDeltaX * localViewport.width,
      normalizedDeltaY * localViewport.height,
    );

    final Offset focalPoint = Offset(
      (gestureData['focalPointX'] as num?)?.toDouble() ?? 0,
      (gestureData['focalPointY'] as num?)?.toDouble() ?? 0,
    );

    print('📥 Gesto desde $senderId');
    print('🔁 Delta escalado: $scaledDelta');

    _applyTransformation(scaledDelta, 1.0, focalPoint);

    // 🧠 Si soy el Leader y el gesto viene de un Linked, reenviarlo a los demás Linked
    if (_isLeader! && senderId != user.currentUser?.email) {
      final forwardedData = {
        ...gestureData,
        'forwarded': true,
        'originalSenderId': senderId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      for (var entry in _connections.entries) {
        if (entry.key != senderId) {
          try {
            entry.value.add(json.encode(forwardedData));
          } catch (e) {
            print('Error reenviando gesto a ${entry.key}: $e');
          }
        }
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile =
          await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      setState(() {
        _isLoadingImage = true;
        _loadProgress = 0.0;
      });

      // Guardamos conexiones por si se reinicia el estado
      final currentConnections = Map<String, WebSocket>.from(_connections);

      final Uint8List imageBytes = await pickedFile.readAsBytes();

      // 🔁 Simulación progresiva de lectura de bytes
      const int chunkSize = 64 * 1024;
      final int totalBytes = imageBytes.length;
      int loaded = 0;
      final buffer = BytesBuilder();

      while (loaded < totalBytes) {
        final end = (loaded + chunkSize).clamp(0, totalBytes);
        buffer.add(imageBytes.sublist(loaded, end));
        loaded = end;

        setState(() {
          _loadProgress = (loaded / totalBytes).clamp(0.0, 0.99);
        });

        await Future.delayed(const Duration(milliseconds: 8));
      }

      final Uint8List completeBytes = buffer.toBytes();

      // ✅ Decode y conversión
      final img.Image? decodedImage = img.decodeImage(completeBytes);

      if (decodedImage == null) throw Exception('No se pudo decodificar.');

      final ui.Image uiImage =
          await ChunkedImageLoader.convertToUiImage(decodedImage);

      if (!mounted) return;

      setState(() {
        _imageBytes = completeBytes;
        _uiImage = uiImage;
        _hasImage = true;
        _isSharing = false;
        _isLoadingImage = false;
        _isGestureSyncEnabled = true;

        if (_connections.isEmpty) {
          _connections = currentConnections;
        }

        _transformationController = TransformationController();
      });

      _updateImageView();
      _broadcastReadyState();
      _checkAllDevicesReady();

      print('✅ Imagen cargada correctamente');
      print('📷 Tamaño imagen: ${_uiImage?.width}x${_uiImage?.height}');
    } catch (e, stackTrace) {
      print('❌ Error al cargar la imagen: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });

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
    if (_uiImage != null && !_isReadyToShare && _isGestureSyncEnabled) {
      final scale = _transformationController.value.getMaxScaleOnAxis();
      final delta = details.focalPointDelta;

      final Rect? senderViewport = _getLeaderViewport();
      if (senderViewport == null) return;

      final double normalizedDeltaX = delta.dx / senderViewport.width;
      final double normalizedDeltaY = delta.dy / senderViewport.height;

      if (normalizedDeltaX.abs() < 0.001 && normalizedDeltaY.abs() < 0.001) {
        return;
      }

      final Offset deltaInImage = delta / scale;
      final Offset focalPoint = details.localFocalPoint;

      // Aplica localmente
      _applyTransformation(deltaInImage, 1.0, focalPoint);

      // Enviar proporción del delta
      _broadcastRelativeGesture(normalizedDeltaX, normalizedDeltaY);
    }
  }

  void _broadcastRelativeGesture(
      double normalizedDeltaX, double normalizedDeltaY) {
    if (!_isSharing || _uiImage == null) return;

    final gestureData = {
      'type': 'relative_gesture',
      'normalizedDeltaX': normalizedDeltaX,
      'normalizedDeltaY': normalizedDeltaY,
      'senderId': myDevice?.id,
    };

    if (_isLeader!) {
      _forwardGestureToAllDevices(gestureData, myDevice?.id ?? 'unknown');
    } else {
      for (var connection in _connections.values) {
        connection.add(json.encode(gestureData));
      }
    }
  }

  void _broadcastGesture(Offset delta, double scale, Offset focalPoint) {
    if (!_isSharing) return;

    print(
        '📤 Enviando gesto desde ${myDevice?.id}: delta=$delta, scale=$scale');

    final Size screenSize = MediaQuery.of(context).size;

    final gestureData = {
      'type': 'sync_gesture',
      'deltaX': delta.dx,
      'deltaY': delta.dy,
      'scale': scale,
      'focalPointX': focalPoint.dx,
      'focalPointY': focalPoint.dy,
      'screenWidth': screenSize.width,
      'screenHeight': screenSize.height,
      'senderId': myDevice?.id,
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
    // ⚠️ Comentado el control
    // if (!_isSharing) return;

    final Matrix4 currentTransform = _transformationController.value;
    final Matrix4 newTransform = Matrix4.copy(currentTransform);

    newTransform.translate(delta.dx, delta.dy);

    print('🎯 Nueva transformación: ${newTransform.getTranslation()}');

    setState(() {
      _transformationController.value = newTransform;
    });
  }

  void _resetSession() {
    setState(() {
      _uiImage = null;
      _imageBytes = null;
      _hasImage = false;
      _isSharing = false;
      _isReadyToShare = false;
      _isFreeSliding = true;
      _isGestureSyncEnabled = false;
      _isQRCodeScanned = false;
      _isLeader = null;
      _initialViewport = null;
      _activeLinkedDeviceId = null;
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
                          if (_isSharing)
                            SpeedDialChild(
                              child: Icon(Icons.logout),
                              label: 'Cerrar room',
                              onTap: () {
                                // Cierra conexiones
                                _connections.forEach((id, socket) {
                                  try {
                                    socket.add(
                                        json.encode({'type': 'stop_session'}));
                                    socket.close();
                                  } catch (e) {
                                    print(
                                        'Error al cerrar conexión con $id: $e');
                                  }
                                });
                                _connections.clear();
                                _connectedDevicesReadyState.clear();

                                _resetSession();

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Sesión finalizada"),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
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
                              // Cierra conexión del Linked
                              _connections.forEach((id, socket) {
                                try {
                                  socket.close();
                                } catch (e) {
                                  print('Error al cerrar conexión con $id: $e');
                                }
                              });

                              _connections.clear();
                              _connectedDevicesReadyState.clear();

                              _resetSession();

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
    if (_isLoadingImage || _isReceivingImage) {
      return LoadingOverlay(
          progress: _isLoadingImage ? _loadProgress : _receiveProgress);
    }

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
                      width: 200,
                      height: 200,
                      child: Lottie.asset('assets/animation/pinch.json'),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Acerca ambos dispositivos',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
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

        Widget imageView = GestureDetector(
          onPanStart: _onPanDragStart,
          onPanUpdate: (DragUpdateDetails details) {
            final fakeScaleDetails = ScaleUpdateDetails(
              focalPoint: details.localPosition,
              localFocalPoint: details.localPosition,
              focalPointDelta: details.delta,
              scale: 1.0, // No usas zoom
            );
            _onInteractionUpdate(fakeScaleDetails);
          },
          onPanEnd: _onPanDragEnd,
          child: AnimatedBuilder(
            animation: _transformationController,
            builder: (context, child) {
              return CustomPaint(
                painter: LazyImagePainter(
                  image: _uiImage!,
                  currentTransform: _transformationController.value,
                  screenSize: MediaQuery.of(context).size,
                  showHighlight: !_isFreeSliding,
                ),
                size: MediaQuery.of(context).size,
              );
            },
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
    if (_isLeader! && _isReadyToShare && !_isFreeSliding) {
      _awaitingLinkedSwipe = true;

      _syncWindowTimer?.cancel();
      _syncWindowTimer = Timer(syncWindowDuration, () {
        _awaitingLinkedSwipe = false;
        print('⌛ Ventana de sincronización expirada');
      });
    }

    setState(() {
      _startHorizontalDragX = details.localPosition.dx;
      _startVerticalDragY = details.localPosition.dy;
      _isLocalSwiping = true;

      if (_isLeader!) {
        leaderSlideY = details.localPosition.dy;
        leaderSlideX = details.localPosition.dx;
      } else {
        linkedSlideY = details.localPosition.dy;
        linkedSlideX = details.localPosition.dx;
      }

      _roleSwipeStates[localRole] = true;
    });

    _broadcastSimultaneousSwipe(true);

    // Reiniciar el temporizador de timeout
    _swipeTimeoutTimer?.cancel();
    _swipeTimeoutTimer = Timer(syncWindowDuration, () {
      print('Timeout de deslizamiento para rol: $localRole');
      _resetSwipeState();
    });
  }

  void _onPanDragUpdate(DragUpdateDetails details) {
    final double currentX = details.localPosition.dx;
    final double currentY = details.localPosition.dy;
    final double dragDistanceX = currentX - _startHorizontalDragX;
    final double dragDistanceY = currentY - _startVerticalDragY;

    const double directionThreshold = 12.0;
    if (dragDistanceX.abs() < directionThreshold &&
        dragDistanceY.abs() < directionThreshold) {
      return; // Ignorar movimientos muy pequeños
    }

    // Calcular el ángulo para obtener dirección cardinal
    final double angle = math.atan2(dragDistanceY, dragDistanceX);
    String newDirection;

    if (angle >= -math.pi / 4 && angle <= math.pi / 4) {
      newDirection = 'right';
    } else if (angle > math.pi / 4 && angle < 3 * math.pi / 4) {
      newDirection = 'down';
    } else if (angle < -math.pi / 4 && angle > -3 * math.pi / 4) {
      newDirection = 'up';
    } else {
      newDirection = 'left';
    }

    // Solo si cambia la dirección, actualiza
    if (_direction != newDirection) {
      _direction = newDirection;
      print('➡️ Dirección detectada: $_direction');
    }

    setState(() {
      _isLocalSwiping = true;
    });

    // Broadcast
    if (_isReadyToShare) {
      _broadcastSimultaneousSwipe(true);
    } else {
      _broadcastSwipeGesture(_direction!);
    }

    // Reiniciar timeout
    _swipeTimeoutTimer?.cancel();
    _swipeTimeoutTimer = Timer(swipeTimeout, () {
      setState(() {
        _isLocalSwiping = false;
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
      _isSwipingLeft = false;
      _isSwipingRight = false;
      _isSwipingDown = false;
      _isSwipingUp = false;
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

    final role = _isLeader! ? 'leader' : 'linked';

    final message = {
      'type': 'swipe_simultaneous',
      'role': role,
      'isSwipping': isSwipping,
      if (!_isLeader!) ...{
        'linkedSlideX': linkedSlideX,
        'linkedSlideY': linkedSlideY,
      },
    };

    for (var connection in _connections.values) {
      try {
        connection.add(json.encode(message));
      } catch (e) {
        print('Error al enviar estado de deslizamiento: $e');
      }
    }
  }

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

class LazyImagePainter extends CustomPainter {
  final ui.Image image;
  final Matrix4 currentTransform;
  final Size screenSize;
  final bool showHighlight;

  LazyImagePainter({
    required this.image,
    required this.currentTransform,
    required this.screenSize,
    this.showHighlight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final translation = currentTransform.getTranslation();
    final scale = currentTransform.getMaxScaleOnAxis();

    // Calcular el área visible de la imagen (viewport)
    double viewportX = -translation.x / scale;
    double viewportY = -translation.y / scale;
    double viewportWidth = screenSize.width / scale;
    double viewportHeight = screenSize.height / scale;

    Rect srcRect = Rect.fromLTWH(
      viewportX,
      viewportY,
      viewportWidth,
      viewportHeight,
    );

    final dstRect = Offset.zero & screenSize;

    print('🖼️ Paint -> translate: ${translation.x}, ${translation.y}');
    print('🖼️ Paint -> viewport: $viewportX, $viewportY');

    // Dibujar solo el recorte visible
    canvas.drawImageRect(image, srcRect, dstRect, Paint());

    // Opcional: dibujar un highlight sobre el área visible
    if (showHighlight) {
      final highlightPaint = Paint()
        ..color = const Color(0xFFFFA91F).withOpacity(0.5)
        ..style = PaintingStyle.fill;

      canvas.drawRect(dstRect, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LazyImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.currentTransform != currentTransform ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.showHighlight != showHighlight;
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
