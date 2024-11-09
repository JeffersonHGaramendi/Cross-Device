import 'dart:developer';

import 'package:crossdevice/auth/signup_screen.dart';
import 'package:crossdevice/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  signUp(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => SignupScreen()),
      );

  homeScreen(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => WifiSyncHome()),
      );

  signIn() async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text, password: _password.text);
    log('User logged');
    homeScreen(context);
  }

  @override
  void initState() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _email.dispose();
    _password.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Flexible(
              flex: 12,
              child: SizedBox(
                width: double.infinity,
                child: Image.asset(
                  'assets/auth/logo_login.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Flexible(
              child: SizedBox(height: 24),
            ),
            SizedBox(
              width: 320,
              height: 33,
              child: Text("Login",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: SizedBox(height: 24),
            ),
            SizedBox(
              width: 320,
              height: 56,
              child: TextField(
                controller: _email,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter Email',
                    labelText: 'Email'),
              ),
            ),
            Flexible(
              child: SizedBox(height: 24),
            ),
            SizedBox(
              width: 320,
              height: 56,
              child: TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter Password',
                    labelText: 'Password'),
              ),
            ),
            Flexible(
              child: SizedBox(height: 17),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              InkWell(
                onTap: () => signUp(context),
                child: Text("Forgot password?",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              )
            ]),
            Flexible(
              child: SizedBox(height: 20),
            ),
            SizedBox(
              width: 320,
              height: 40,
              child: ElevatedButton(
                //label: "Login",
                onPressed: () {
                  if (_email.text.isNotEmpty && _password.text.isNotEmpty) {
                    signIn();
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF0067FF),
                    foregroundColor: Colors.white),
                child: Text(
                  'Iniciar sesión',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
            Flexible(
              child: SizedBox(height: 17),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Don't have an account? "),
              InkWell(
                onTap: () => signUp(context),
                child: Text("Signup",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0067FF))),
              )
            ]),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
