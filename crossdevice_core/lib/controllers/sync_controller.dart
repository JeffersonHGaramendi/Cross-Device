import '../services/websocket_manager.dart';
import '../services/image_sync_service.dart';
import '../services/gesture_sync_service.dart';
import '../models/device_info.dart';

class SyncController {
  static final SyncController _instance = SyncController._internal();

  factory SyncController() => _instance;

  late WebSocketManager webSocketManager;
  late ImageSyncService imageSyncService;
  late GestureSyncService gestureSyncService;

  bool isLeader = false;
  bool isReadyToShare = false;
  bool isSharing = false;
  bool isGestureSyncEnabled = false;

  DeviceInfo? myDevice;
  List<DeviceInfo> connectedDevices = [];

  SyncController._internal() {
    webSocketManager = WebSocketManager(
      onMessageReceived: _handleIncomingMessage,
      onDisconnected: _handleDisconnection,
      onConnected: _handleConnection,
    );
    imageSyncService = ImageSyncService();
    gestureSyncService = GestureSyncService();
  }

  void init() {
    webSocketManager.startServer();
  }

  void _handleIncomingMessage(String message, String connectionId) {
    // TODO: Procesar el mensaje recibido (ej. gestures, images, states)
  }

  void _handleConnection(String connectionId) {
    // TODO: Agregar conexión nueva
  }

  void _handleDisconnection(String connectionId) {
    // TODO: Limpiar dispositivos al desconectarse
  }

  void dispose() {
    webSocketManager.dispose();
  }
}
