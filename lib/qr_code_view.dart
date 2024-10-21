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
    return Center(
      child: _isLoading
          ? CircularProgressIndicator()
          : Container(
              constraints: BoxConstraints(
                maxWidth: 300,
                maxHeight: 300,
              ),
              child: SizedBox(
                width: 250,
                height: 250,
                child: QrImageView(
                  data: json.encode({
                    'ip': _localIp,
                  }), // IP o los datos que ha mostrar en el QR
                  version: QrVersions.auto,
                  size: 250.0,
                ),
              ),
            ),
    );
  }
}
