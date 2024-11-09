import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeViewHasImage extends StatefulWidget {
  const QrCodeViewHasImage({super.key});

  @override
  State<QrCodeViewHasImage> createState() => _QrCodeViewHasImageState();
}

class _QrCodeViewHasImageState extends State<QrCodeViewHasImage> {
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? CircularProgressIndicator()
            : Center(
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
                        'ip': _localIp,
                      }),
                      version: QrVersions.auto,
                      size: 250.0,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
