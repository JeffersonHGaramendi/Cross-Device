import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeView extends StatefulWidget {
  const QrCodeView({super.key});

  @override
  State<QrCodeView> createState() => _QrCodeViewState();
}

class _QrCodeViewState extends State<QrCodeView> {
  final NetworkInfo _networkInfo = NetworkInfo();
  String _localIp = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _getLocalIp();
  }

  void _getLocalIp() async {
    String? ip = await _networkInfo.getWifiIP();
    if (ip != null) {
      setState(() {
        _localIp = ip;
        _isLoading = false;
        print('Local IP: $ip');
      });
    } else {
      _isLoading = false;
      print('Failed to get local IP');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? CircularProgressIndicator()
              : Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 64,
                      ),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Color(0xFFDDEDFF), // Color de fondo
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.share,
                            color: Color(0xFF0067FF), size: 28),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Proyector,',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Comparte este QR con los dispositivos que deseas vincular.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF939393),
                        ),
                        textAlign: TextAlign.left,
                      ),
                      SizedBox(height: 30),
                      Center(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: 300,
                            maxHeight: 300,
                          ),
                          child: SizedBox(
                            width: 250,
                            height: 250,
                            child: QrImageView(
                              data: 'room://$_localIp',
                              version: QrVersions.auto,
                              size: 250.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
