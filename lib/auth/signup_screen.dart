import 'dart:developer';

import 'package:crossdevice/auth/login_screen.dart';
import 'package:crossdevice/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    super.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25),
        child: Column(
          children: [
            const Spacer(),
            const Text("Signup",
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
            const SizedBox(
              height: 50,
            ),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter Name',
                  labelText: 'Name'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter Email',
                  labelText: 'Email'),
            ),
            const SizedBox(height: 20),
            TextField(
              //isPassword: true,
              controller: _password,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter Password',
                  labelText: 'Password'),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                if (_email.text.isNotEmpty &&
                    _password.text.isNotEmpty &&
                    _name.text.isNotEmpty) _signup();
              },
              child: Text('Sign Up'),
            ),
            const SizedBox(height: 5),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("Already have an account? "),
              InkWell(
                onTap: () => loginScreenFromSignUp(context),
                child: const Text("Login", style: TextStyle(color: Colors.red)),
              )
            ]),
            const Spacer()
          ],
        ),
      ),
    );
  }

  loginScreenFromSignUp(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );

  homeScreenFromSignUp(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => WifiSyncHome()),
      );

  _signup() async {
    final user = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text, password: _password.text);
    if (user != null) {
      log("User Created Succesfully");
      homeScreenFromSignUp(context);
    }
  }
}
