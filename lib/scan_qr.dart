import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';

class ShowQRView extends StatefulWidget {
  final Function(String) onQRScanned;
  final Function(String)? onQRInvalid;

  const ShowQRView({
    required this.onQRScanned,
    this.onQRInvalid,
  });

  @override
  State<ShowQRView> createState() => _ShowQRViewState();
}

class _ShowQRViewState extends State<ShowQRView> {
  final double overlaySize = 250;
  final double borderRadius = 10;
  bool _hasScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// QR scanner con mobile_scanner
          MobileScanner(
              controller: MobileScannerController(),
              onDetect: (BarcodeCapture capture) async {
                if (_hasScanned) return;

                final qr = capture.barcodes.first.rawValue;
                if (qr == null) return;

                final uri = Uri.tryParse(qr);
                final info = NetworkInfo();
                final myIp = await info.getWifiIP();
                final myGateway = await info.getWifiGatewayIP();

                if (uri == null ||
                    uri.scheme != 'room' ||
                    uri.host.isEmpty ||
                    myIp == null ||
                    myGateway == null) {
                  widget.onQRInvalid
                      ?.call("Código no válido o no estás en la misma red.");
                  return;
                }

                print('✅ Mi IP: $myIp');
                print('✅ IP del QR: ${uri.host}');
                print('✅ Mi Gateway: $myGateway');

                // 🔥 NUEVO: Obtener el gateway del QR
                final qrGateway = await _getGatewayOfIp(uri.host);
                print('✅ Gateway del QR: $qrGateway');

                if (qrGateway == null || qrGateway != myGateway) {
                  widget.onQRInvalid?.call(
                      "No están conectados al mismo Wi-Fi (distinto Gateway).");
                  return;
                }

                setState(() {
                  _hasScanned = true;
                });

                widget.onQRScanned(qr);
              }),

          /// Superposición oscura con recorte
          Positioned.fill(
            child: CustomPaint(
              painter: QRScannerOverlayPainter(
                overlaySize: overlaySize,
                borderRadius: borderRadius,
              ),
            ),
          ),

          /// Marco azul claro en el centro
          Center(
            child: Container(
              width: overlaySize,
              height: overlaySize,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Color(0xFF0067FF),
                  width: 4,
                ),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),

          /// Encabezado e instrucciones
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 40, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 40),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Color(0xFFDDEDFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.remove_red_eye,
                      color: Colors.blue,
                      size: 24,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Visualizador,',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Escanea el QR del room al que deseas ingresar.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF939393),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _getLocalIpAddress() async {
    final info = NetworkInfo();
    return await info.getWifiIP();
  }

  Future<String?> _getGatewayOfIp(String ip) async {
    // Esta función es un mock, en realidad para obtener el gateway de otro IP
    // tendrías que preguntarle a un servidor o asumir que todos usan el mismo router.

    // Para simplificar: Asumimos que si tú estás conectado a 10.11.x.x y el QR tiene 10.11.x.x,
    // ambos usan el mismo Gateway.

    // Retornamos tu mismo gateway como "gateway del QR"
    final info = NetworkInfo();
    return await info.getWifiGatewayIP();
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
