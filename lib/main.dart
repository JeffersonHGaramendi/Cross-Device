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
import 'package:http/http.dart' as http;
import 'dart:math' as math;

import 'package:crossdevice/auth/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
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
  final user = FirebaseAuth.instance.currentUser;
  Map<String, WebSocket> _connections = {};

  bool _isServerRunning = false;
  String _localIp = '';
  String _debugInfo = '';
  HttpServer? _server;

  Uint8List? _imageBytes;
  bool _isSharing = false;
  Map<String, Rect> _sharedImagePortions = {};
  TransformationController _transformationController =
      TransformationController();
  ui.Image? _uiImage;

  bool _isSyncingGesture = false;
  Timer? _syncTimer;

  List<DeviceInfo> connectedDevices = [];
  DeviceInfo? myDevice;

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

    webSocket.add(json.encode({'type': 'request_screen_size'}));

    if (_imageBytes != null) {
      _shareImageWithNewConnection(webSocket);
    }

    webSocket.listen(
      (message) {
        _addDebugInfo('Received message from $connectionId: $message');
        _handleIncomingMessage(message, connectionId);
      },
      onError: (error) => _addDebugInfo('WebSocket error: $error'),
      onDone: () {
        _addDebugInfo('WebSocket connection closed');
        _connections.remove(connectionId);
        connectedDevices.removeWhere((device) => device.id == connectionId);
        _calculateImagePortions();
        setState(() {});
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

  void _toggleSharing() {
    if (_imageBytes != null) {
      setState(() {
        _isSharing = !_isSharing;
      });
      if (_isSharing) {
        _broadcastImageMetadata();
      }
    }
  }

  void _broadcastImageMetadata() {
    if (_imageBytes != null) {
      final base64Image = base64Encode(_imageBytes!);
      final metadata = {
        'type': 'image_metadata',
        'data': base64Image,
        'sender': user?.email ?? 'unknown',
      };
      for (var connection in _connections.values) {
        connection.add(json.encode(metadata));
      }
    } else {
      print('No user available to share');
    }
  }

  void _handleIncomingMessage(dynamic message, String connectionId) {
    Map<String, dynamic> messageData;

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
        _handleReceivedImage(messageData['data'], messageData['sender']);
        break;
      case 'image_portion':
        _handleReceivedImagePortion(
            messageData['deviceId'], messageData['portion']);
        break;
      case 'sync_gesture':
        _handleSyncGesture(List<double>.from(messageData['matrix']));
        break;
      case 'request_screen_size':
        _sendScreenSize(connectionId);
        break;
      case 'reset_view':
        _resetView();
        break;
      default:
        print('Unknown message type: ${messageData['type']}');
    }
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
    if (_uiImage == null || connectedDevices.isEmpty) {
      print(
          "No se pueden calcular las porciones: imagen o dispositivos no disponibles");
      return;
    }

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

      print("Porción calculada para ${device.id}: ${device.portion}");

      if (device.id == myDevice?.id) {
        setState(() {
          myDevice = device;
        });
        print(
            "Actualizada la porción para mi dispositivo: ${myDevice?.portion}");
      }
    }

    _addDebugInfo(
        'Image portions calculated. My portion: ${myDevice?.portion}');
    _broadcastImagePortions();
    setState(() {}); // Forzar actualización de la UI
    print("Porciones calculadas y estado actualizado");
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
    print("Porciones de imagen transmitidas a todos los dispositivos");
  }

  void _handleReceivedImage(String base64Image, String sender) {
    print("Recibiendo imagen de: $sender");
    final Uint8List imageBytes = base64Decode(base64Image);
    print("Imagen recibida: ${imageBytes.length} bytes");
    ui.decodeImageFromList(imageBytes, (ui.Image result) {
      print("Imagen decodificada: ${result.width}x${result.height}");
      setState(() {
        _uiImage = result;
        _imageBytes = imageBytes;
        _isSharing = true;
      });
      _calculateImagePortions();
      _updateImageView();
      print("Estado actualizado y vista de imagen actualizada");
    });
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

  void _handleSyncGesture(List<double> matrixValues) {
    if (!_isSyncingGesture) {
      final receivedTransform = Matrix4.fromList(matrixValues);
      setState(() {
        _transformationController.value = receivedTransform;
      });
      print("Gesto sincronizado aplicado: $receivedTransform");
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker _picker = ImagePicker();
    final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final Uint8List imageBytes = await pickedFile.readAsBytes();
      final ui.Image uiImage = await _loadImage(imageBytes);
      setState(() {
        _imageBytes = imageBytes;
        _uiImage = uiImage;
        _isSharing = true;
        _sharedImagePortions.clear();
      });
      print("Imagen seleccionada: ${imageBytes.length} bytes");
      _calculateImagePortions();
      _updateImageView();
      _broadcastImageToAllConnections();
    } else {
      print("No se seleccionó ninguna imagen");
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

  void _broadcastImageToAllConnections() {
    print("Compartiendo imagen con ${_connections.length} dispositivos");
    for (var connection in _connections.values) {
      _shareImageWithNewConnection(connection);
    }
  }

  // Asegúrate de que esta función esté codificando correctamente el mensaje
  void _shareImageWithNewConnection(WebSocket connection) {
    if (_imageBytes != null) {
      final base64Image = base64Encode(_imageBytes!);
      final metadata = {
        'type': 'image_metadata',
        'data': base64Image,
        'sender': 'device_${_localIp}',
      };
      print("Enviando imagen de ${base64Image.length} caracteres");
      connection.add(json.encode(metadata));
    } else {
      print('No hay imagen disponible para compartir'); // Depuración
    }
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (_isSharing && _uiImage != null) {
      _isSyncingGesture = true;
      _syncTimer?.cancel();
      _syncTimer = Timer(Duration(milliseconds: 100), () {
        _isSyncingGesture = false;
      });

      final updatedTransform = Matrix4.identity()
        ..translate(details.focalPoint.dx, details.focalPoint.dy)
        ..scale(details.scale);

      setState(() {
        _transformationController.value = updatedTransform;
      });

      final gestureData = {
        'type': 'sync_gesture',
        'matrix': updatedTransform.storage,
      };

      for (var connection in _connections.values) {
        connection.add(json.encode(gestureData));
      }

      print(
          "Gesto sincronizado: scale=${details.scale}, focalPoint=${details.focalPoint}");
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
      appBar: AppBar(
        title: Text('Image Sharing App'),
        actions: [
          IconButton(
            icon: Icon(Icons.qr_code),
            onPressed: _showQRCode,
            tooltip: 'Show QR Code',
          ),
          IconButton(
            icon: Icon(Icons.qr_code_scanner),
            onPressed: _scanQRCode,
            tooltip: 'Scan QR Code',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _resetView,
            tooltip: 'Reset View',
          ),
          IconButton(
            icon: Icon(_isSharing ? Icons.stop : Icons.play_arrow),
            onPressed: _toggleSharing,
            tooltip: _isSharing ? 'Stop Sharing' : 'Start Sharing',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildImageView(),
          ),
          if (_debugInfo.isNotEmpty)
            Container(
              height: 100,
              child: SingleChildScrollView(
                child: Text(_debugInfo),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickImage,
        child: Icon(Icons.add_photo_alternate),
        tooltip: 'Pick Image',
      ),
    );
  }

  Widget _buildImageView() {
    if (_imageBytes == null || _uiImage == null) {
      return Center(child: Text('No hay imagen seleccionada'));
    }

    if (myDevice == null) {
      return Center(child: Text('Esperando información del dispositivo...'));
    }

    if (myDevice!.portion == Rect.zero) {
      return Center(child: Text('Calculando porción de la imagen...'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onDoubleTap: _resetView,
          child: InteractiveViewer(
            transformationController: _transformationController,
            onInteractionUpdate: _onInteractionUpdate,
            child: CustomPaint(
              painter: ImagePainter(
                image: _uiImage!,
                portion: myDevice!.portion,
                constraints: constraints,
                transform: _transformationController.value,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            ),
          ),
        );
      },
    );
  }

  void _showQRCode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: SizedBox(
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
  }

  void _scanQRCode() {
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
  }

  loginScreenFromHome(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );

  void _resetView() {
    setState(() {
      _transformationController.value = Matrix4.identity();
    });
    _broadcastResetView();
  }

  void _broadcastResetView() {
    final resetData = {
      'type': 'reset_view',
    };
    for (var connection in _connections.values) {
      connection.add(json.encode(resetData));
    }
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

class ImagePainter extends CustomPainter {
  final ui.Image image;
  final Rect portion;
  final BoxConstraints constraints;
  final Matrix4 transform;

  ImagePainter({
    required this.image,
    required this.portion,
    required this.constraints,
    required this.transform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    final imageAspectRatio = image.width / image.height;
    final screenAspectRatio = size.width / size.height;

    double scale;
    if (imageAspectRatio > screenAspectRatio) {
      scale = size.width / (image.width * portion.width);
    } else {
      scale = size.height / (image.height * portion.height);
    }

    final srcRect = Rect.fromLTWH(
      portion.left * image.width,
      portion.top * image.height,
      portion.width * image.width,
      portion.height * image.height,
    );

    final dstRect = Rect.fromLTWH(
      0,
      0,
      srcRect.width * scale,
      srcRect.height * scale,
    );

    canvas.save();
    canvas.transform(transform.storage);
    canvas.drawImageRect(image, srcRect, dstRect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.portion != portion ||
        oldDelegate.transform != transform;
  }
}
