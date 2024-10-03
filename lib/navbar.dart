import 'dart:developer';

import 'package:crossdevice/auth/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class Navbar extends StatelessWidget {
  final user = FirebaseAuth.instance;

  Navbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(children: <Widget>[
        DrawerHeader(
          decoration: BoxDecoration(
            color: Colors.grey[200],
          ),
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey[300],
                child: Icon(
                  Icons.person,
                  size: 50,
                  color: Colors.grey,
                ),
              ),
              SizedBox(width: 16), // Espacio entre la imagen y el texto
              Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Textos a la izquierda
                mainAxisAlignment: MainAxisAlignment
                    .center, // Centra verticalmente dentro del Drawer
                children: [
                  Text(
                    'John Doe',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${user.currentUser?.email}',
                    style: TextStyle(
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ListTile(
          leading: Icon(Icons.person),
          title: Text('My Account'),
          onTap: () {
            // "My Account"
          },
        ),
        Spacer(),
        SpacerTile(), // Espaciador entre las opciones y el logout
        ListTile(
          leading: Icon(Icons.logout),
          title: Text('Log Out'),
          onTap: () {
            logOut(context); // "Log Out"
          },
        ),
      ]),
    );
  }

  loginScreenFromHome(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );

  logOut(BuildContext context) {
    user.signOut();
    log('User offline');
    loginScreenFromHome(context);
  }
}

//LÍNEA DE DIVISIÓN
class SpacerTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.0),
      child: Divider(
        indent: 20,
        endIndent: 20,
        thickness: 2,
        color: Colors.grey[300], // Color del divisor
      ),
    );
  }
}
