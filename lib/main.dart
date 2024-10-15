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

  Timer? _syncTimer;
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

  bool _isImageDraggingEnabled = true;

  bool _isSwipingSimultaneously = false;
  Map<String, bool> _devicesSwipingState = {};
  Timer? _swipeTimer;
  bool _isLocalSwiping = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _getLocalIp();
    _startServer();
    //_initializeLocalDevice();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeLocalDevice(); // Ahora es seguro llamar aquí a MediaQuery
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
    _connections[connectionId] = webSocket;
    _addDebugInfo('Client connected: $connectionId');

    setState(() {
      _connectedDevicesReadyState[connectionId] = false;
    });

    webSocket.add(json.encode({'type': 'request_screen_size'}));
    _broadcastReadyState();

    webSocket.listen(
      (message) {
        _addDebugInfo('Received message from $connectionId: $message');
        _handleIncomingMessage(message, connectionId);
      },
      onError: (error) => _addDebugInfo('WebSocket error: $error'),
      onDone: () {
        _addDebugInfo('WebSocket connection closed');
        _connections.remove(connectionId);
        setState(() {
          _connectedDevicesReadyState.remove(connectionId);
        });
        _checkAllDevicesReady();
      },
    );
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
          _addDebugInfo('Received message: $message');
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

  void _startSharing() {
    if (_imageBytes != null && !_isSharing) {
      setState(() {
        _isSharing = true;
      });
      _broadcastImageMetadata();
      print("Comenzando a compartir la imagen");
    }
  }

  void _stopSharing() {
    if (_isSharing) {
      setState(() {
        _isSharing = false;
      });
      final stopSharingData = {
        'type': 'stop_sharing',
      };
      for (var connection in _connections.values) {
        connection.add(json.encode(stopSharingData));
      }
      print("Dejando de compartir la imagen");
    }
  }

  void _broadcastImageMetadata() {
    if (_imageBytes != null) {
      final base64Image = base64Encode(_imageBytes!);
      final metadata = {
        'type': 'image_shared',
        'data': base64Image,
        'sender': user.currentUser?.email ?? 'unknown',
        'transform': _deviceSpecificTransform.storage.toString(),
      };
      for (var connection in _connections.values) {
        connection.add(json.encode(metadata));
      }
      print("Imagen compartida con ${_connections.length} dispositivos");
    } else {
      print('No hay imagen disponible para compartir');
    }
  }

  void _handleImageShared(
      String base64Image, String sender, String? transformString) {
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
    });
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
    Map<String, dynamic> messageData = json.decode(message);

    if (message is String) {
      try {
        messageData = json.decode(message);
      } catch (e) {
        print('Error decodificando mensaje: $e');
        return;
      }
    } else if (message is Map<String, dynamic>) {
      messageData = message;
    } else {
      print('Tipo de mensaje inesperado: ${message.runtimeType}');
      return;
    }

    print("Mensaje recibido de tipo: ${messageData['type']}");

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
        _handleSimultaneousSwipe(connectionId, messageData['isSwipping']);
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
      if ((direction == 'left' && _isSwipingLeft) ||
          (direction == 'right' && _isSwipingRight)) {
        _checkSimultaneousSwipe();
      }
    }
  }

  void _handleSimultaneousSwipe(String connectionId, bool isSwipping) {
    setState(() {
      _devicesSwipingState[connectionId] = isSwipping;
    });
    _checkSimultaneousSwipe();
  }

  void _checkSimultaneousSwipe() {
    bool allDevicesSwipping =
        _devicesSwipingState.values.every((isSwipping) => isSwipping);
    if (allDevicesSwipping &&
        _isLocalSwiping &&
        _isReadyToShare &&
        _allDevicesReady) {
      _initiateImageSharing();
    }
  }

  void _initiateImageSharing() {
    if (_hasImage) {
      _broadcastImageMetadata();
      setState(() {
        _isGestureSyncEnabled = true;
        _isSharing = true;
      });
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
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final Uint8List imageBytes = await pickedFile.readAsBytes();
      final ui.Image uiImage = await _loadImage(imageBytes);
      setState(() {
        _imageBytes = imageBytes;
        _uiImage = uiImage;
        _hasImage = true;
        _isSharing = false; // No compartir automáticamente
      });
      _calculateImagePortions();
      _updateImageView();
      _broadcastReadyState(); // Actualizar el estado de tener imagen
      _checkAllDevicesReady(); // Verificar si todos están listos después de cargar la imagen
    }
  }

  Future<ui.Image> _loadImage(Uint8List imageBytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(imageBytes, (ui.Image img) {
      print("Imagen cargada: ${img.width}x${img.height}");
      completer.complete(img);
    });
    return completer.future;
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
    if ((_imageBytes == null || _uiImage == null) && _isLeader!) {
      return _buildQRCodeView();
    }

    if (!_isLeader! && !_isQRCodeScanned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanQRCode();
      });
      return Center(child: CircularProgressIndicator());
    }

    if ((_imageBytes == null || _uiImage == null) &&
        !_isLeader! &&
        _isQRCodeScanned) {
      return Center(
        child: Text(
          'Esperando una imagen...',
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onHorizontalDragStart: _isReadyToShare && !_isFreeSliding
              ? _onHorizontalDragStart
              : null,
          onHorizontalDragUpdate: _isReadyToShare && !_isFreeSliding
              ? _onHorizontalDragUpdate
              : null,
          onHorizontalDragEnd:
              _isReadyToShare && !_isFreeSliding ? _onHorizontalDragEnd : null,
          onVerticalDragStart:
              _isReadyToShare && !_isFreeSliding ? _onVerticalDragStart : null,
          onVerticalDragUpdate:
              _isReadyToShare && !_isFreeSliding ? _onVerticalDragUpdate : null,
          onVerticalDragEnd:
              _isReadyToShare && !_isFreeSliding ? _onVerticalDragEnd : null,
          child: InteractiveViewer(
            transformationController:
                TransformationController(_deviceSpecificTransform),
            onInteractionUpdate: _onInteractionUpdate,
            maxScale: 10.0,
            child: CustomPaint(
              painter: ImagePainter(
                image: _uiImage!,
                initialViewport: _initialViewport,
                showHighlight:
                    !_isFreeSliding, // Solo mostrar el resaltado cuando no esté en modo de deslizamiento libre
              ),
              size:
                  Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble()),
            ),
          ),
        );
      },
    );
  }

  // HORIZONTAL
  void _onHorizontalDragStart(DragStartDetails details) {
    _startHorizontalDragX = details.localPosition.dx;
    _isLocalSwiping = true;
    _broadcastSimultaneousSwipe(true);
    _startSwipeTimer();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isLocalSwiping) return;

    double currentX = details.localPosition.dx;
    double dragDistance = currentX - _startHorizontalDragX;

    setState(() {
      _isSwipingLeft = dragDistance < -20;
      _isSwipingRight = dragDistance > 20;
    });

    _resetSwipeTimer();
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _isLocalSwiping = false;
    _broadcastSimultaneousSwipe(false);
    _cancelSwipeTimer();

    setState(() {
      _isSwipingLeft = false;
      _isSwipingRight = false;
    });
  }

  // VERTICAL
  void _onVerticalDragStart(DragStartDetails details) {
    _startVerticalDragY = details.localPosition.dy;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    double currentY = details.localPosition.dy;
    double dragDistance = currentY - _startVerticalDragY;

    setState(() {
      _isSwipingDown = dragDistance < -20;
      _isSwipingUp = dragDistance > 20;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isReadyToShare &&
        _allDevicesReady &&
        (_isSwipingDown || _isSwipingUp)) {
      _initiateImageSharing();
    }
    _broadcastSwipeGesture(_isSwipingDown ? 'down' : 'up');

    setState(() {
      _isSwipingDown = false;
      _isSwipingUp = false;
    });
  }

  // TIMER SWIPE
  void _startSwipeTimer() {
    _swipeTimer = Timer(Duration(milliseconds: 500), () {
      _isLocalSwiping = false;
      _broadcastSimultaneousSwipe(false);
    });
  }

  void _resetSwipeTimer() {
    _cancelSwipeTimer();
    _startSwipeTimer();
  }

  void _cancelSwipeTimer() {
    _swipeTimer?.cancel();
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

  void _broadcastSimultaneousSwipe(bool isSwipping) {
    final swipeData = {
      'type': 'swipe_simultaneous',
      'isSwipping': isSwipping,
    };
    for (var connection in _connections.values) {
      connection.add(json.encode(swipeData));
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
    for (var connection in _connections.values) {
      connection.close();
    }
    _syncTimer?.cancel();
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
