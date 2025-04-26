import 'dart:ui';

class DeviceInfo {
  final String id;
  Rect portion;
  Size size;

  DeviceInfo({
    required this.id,
    required this.portion,
    required this.size,
  });
}