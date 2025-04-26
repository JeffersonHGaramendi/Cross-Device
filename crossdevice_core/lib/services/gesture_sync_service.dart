import 'dart:ui';
import 'package:flutter/material.dart';

class GestureSyncService {
  void applyTransformation(Matrix4 transform, Offset delta) {
    transform.translate(delta.dx, delta.dy);
  }

  Map<String, dynamic> createGesturePayload(
    Offset delta,
    double scale,
    Offset focalPoint,
  ) {
    return {
      'type': 'sync_gesture',
      'deltaX': delta.dx,
      'deltaY': delta.dy,
      'scale': scale,
      'focalPointX': focalPoint.dx,
      'focalPointY': focalPoint.dy,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
