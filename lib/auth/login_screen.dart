import 'dart:developer';

import 'package:crossdevice/auth/signup_screen.dart';
import 'package:crossdevice/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25),
        child: Column(
          children: [
            const Spacer(),
            const Text("Login",
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
            const SizedBox(height: 50),
            TextField(
              controller: _email,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter Email',
                  labelText: 'Email'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter Password',
                  labelText: 'Password'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              //label: "Login",
              onPressed: () {
                if (_email.text.isNotEmpty && _password.text.isNotEmpty) {
                  signIn();
                }
              },
              child: Text('Login'),
            ),
            const SizedBox(height: 5),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("Already have an account? "),
              InkWell(
                onTap: () => signUp(context),
                child:
                    const Text("Signup", style: TextStyle(color: Colors.red)),
              )
            ]),
            const Spacer()
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _email.dispose();
    _password.dispose();
  }
}
