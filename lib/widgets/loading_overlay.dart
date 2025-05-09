import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  final double progress; // Valor entre 0.0 y 1.0

  const LoadingOverlay({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 0.99);
    final percentage = (clampedProgress * 100).toInt();
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      color: Colors.white.withOpacity(0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Cargando imagen...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: screenWidth * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: clampedProgress,
                      minHeight: 12,
                      backgroundColor: Colors.blue.shade100,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF3B82F6), // azul similar al de la imagen
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$percentage% completed',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
