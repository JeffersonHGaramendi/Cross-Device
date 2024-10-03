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
      appBar: AppBar(
        title: Text('Choose Role'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 20,
            ),
            ElevatedButton(
                onPressed: () {
                  widget.isLeader(true);
                },
                child: Text('Leader')),
            SizedBox(
              height: 10,
            ),
            ElevatedButton(
                onPressed: () {
                  widget.isLeader(false);
                },
                child: Text('Linked'))
          ],
        ),
      ),
    );
  }
}
