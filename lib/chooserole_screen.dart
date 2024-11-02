import 'package:flutter/material.dart';

class ChooseroleScreen extends StatefulWidget {
  final Function(bool) isLeader;

  const ChooseroleScreen({super.key, required this.isLeader});

  @override
  State<ChooseroleScreen> createState() => _ChooseroleScreenState();
}

class _ChooseroleScreenState extends State<ChooseroleScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: Column(
              children: [
                const Spacer(),
                SizedBox(
                  width: 320,
                  height: 66,
                  child: Text(
                    "¿Qué tipo de usuario serás hoy?",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  height: 24,
                ),
                Container(
                  width: 320,
                  padding: EdgeInsets.all(20),
                  margin: EdgeInsets.only(
                      bottom: 16), // Espacio entre los Containers
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.share,
                        color: Color(0xFF0067FF),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Proyector',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Serás quien comparta imágenes.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF939393),
                        ),
                      ),
                      SizedBox(height: 24),
                      SizedBox(
                        width: 288,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () {
                            widget.isLeader(true);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF0067FF),
                              foregroundColor: Colors.white),
                          child: Text(
                            'Seleccionar',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 24,
                ),
                Container(
                  width: 320,
                  padding: EdgeInsets.all(20),
                  margin: EdgeInsets.only(
                      bottom: 16), // Espacio entre los Containers
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.remove_red_eye,
                        color: Color(0xFF0067FF),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Visualizador',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Serás quien visualizará las imágenes.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF939393),
                        ),
                      ),
                      SizedBox(height: 24),
                      SizedBox(
                        width: 288,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () {
                            widget.isLeader(false);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF0067FF),
                              foregroundColor: Colors.white),
                          child: Text(
                            'Seleccionar',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
