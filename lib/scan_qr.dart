import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

class QRViewExample extends StatefulWidget {
  final Function(String) onQRScanned;

  QRViewExample({required this.onQRScanned});

  @override
  State<StatefulWidget> createState() => _QRViewExampleState();
}

class _QRViewExampleState extends State<QRViewExample> {
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final double overlaySize = 250;
  final double borderRadius = 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // QRView para escanear el código QR
          QRView(
            key: qrKey,
            onQRViewCreated: _onQRViewCreated,
          ),
          // ClipPath para hacer la parte del QR transparente
          Positioned.fill(
            child: CustomPaint(
              painter: QRScannerOverlayPainter(
                overlaySize: overlaySize,
                borderRadius: borderRadius,
              ),
            ),
          ),
          // Marco verde visible sin superposición oscura
          Center(
            child: Container(
              width: overlaySize,
              height: overlaySize,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.green,
                  width: 4,
                ),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),
          // Texto opcional para guiar al usuario
          // Positioned(
          //   bottom: 50,
          //   left: 0,
          //   right: 0,
          //   child: Text(
          //     'Posiciona el QR dentro del marco',
          //     textAlign: TextAlign.center,
          //     style: TextStyle(
          //       color: Colors.white,
          //       fontSize: 18,
          //       fontWeight: FontWeight.bold,
          //     ),
          //   ),
          // ),
        ],
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

// Painter personalizado para crear la superposición con un área transparente
class QRScannerOverlayPainter extends CustomPainter {
  final double overlaySize;
  final double borderRadius;

  QRScannerOverlayPainter(
      {required this.overlaySize, required this.borderRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5); // Fondo oscuro semi-transparente

    // Definir el área del rectángulo central (el marco para el QR)
    final double horizontalPadding = (size.width - overlaySize) / 2;
    final double verticalPadding = (size.height - overlaySize) / 2;

    // Dibujar un fondo oscuro completo
    Path fullScreenPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Crear un rectángulo transparente en el centro
    Path transparentRect = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(
            horizontalPadding, verticalPadding, overlaySize, overlaySize),
        Radius.circular(borderRadius),
      ));

    // Restar el área transparente del fondo oscuro
    Path finalPath =
        Path.combine(PathOperation.difference, fullScreenPath, transparentRect);

    // Dibujar el fondo con el área recortada
    canvas.drawPath(finalPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
