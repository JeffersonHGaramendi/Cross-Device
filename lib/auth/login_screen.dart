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
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _errorMessage = '';

  signUp(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => SignupScreen()),
      );

  homeScreen(BuildContext context) => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => WifiSyncHome()),
      );

  // Función para mostrar mensajes de error personalizados
  String _getErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'user-not-found':
        return 'No existe una cuenta con este correo electrónico.';
      case 'wrong-password':
        return 'La contraseña es incorrecta.';
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'user-disabled':
        return 'Esta cuenta ha sido deshabilitada.';
      case 'too-many-requests':
        return 'Demasiados intentos fallidos. Intenta más tarde.';
      case 'invalid-credential':
        return 'Las credenciales proporcionadas son incorrectas.';
      case 'network-request-failed':
        return 'Error de conexión. Verifica tu internet.';
      case 'weak-password':
        return 'La contraseña es muy débil.';
      default:
        return 'Ha ocurrido un error. Intenta nuevamente.';
    }
  }

  // Función para validar el formato del email
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  signIn() async {
    // Limpiar mensaje de error anterior
    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    // Validaciones básicas
    if (_email.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Por favor ingrese su correo electrónico.';
        _isLoading = false;
      });
      return;
    }

    if (!_isValidEmail(_email.text.trim())) {
      setState(() {
        _errorMessage = 'Por favor ingrese un correo electrónico válido.';
        _isLoading = false;
      });
      return;
    }

    if (_password.text.isEmpty) {
      setState(() {
        _errorMessage = 'Por favor ingrese su contraseña.';
        _isLoading = false;
      });
      return;
    }

    if (_password.text.length < 6) {
      setState(() {
        _errorMessage = 'La contraseña debe tener al menos 6 caracteres.';
        _isLoading = false;
      });
      return;
    }

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      log('User logged successfully');

      // Limpiar campos y navegar
      _email.clear();
      _password.clear();

      if (mounted) {
        homeScreen(context);
      }
    } on FirebaseAuthException catch (e) {
      log('Firebase Auth Error: ${e.code}');
      setState(() {
        _errorMessage = _getErrorMessage(e.code);
        _isLoading = false;
      });
    } catch (e) {
      log('General Error: $e');
      setState(() {
        _errorMessage = 'Ha ocurrido un error inesperado. Intenta nuevamente.';
        _isLoading = false;
      });
    }
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
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: 320),
                child: Text("Login",
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
            Flexible(
              child: SizedBox(height: 24),
            ),
            // Email Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: 320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 56,
                      child: TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Enter Email',
                          labelText: 'Email',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    // Mensaje de error específico para email
                    if (_errorMessage.isNotEmpty &&
                        (_errorMessage.contains('correo') ||
                            _errorMessage.contains('email')))
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 12),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red.shade700, size: 16),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _errorMessage,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: SizedBox(height: 24),
            ),
            // Password Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: 320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 56,
                      child: TextField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Enter Password',
                          labelText: 'Password',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    // Mensaje de error específico para contraseña
                    if (_errorMessage.isNotEmpty &&
                        _errorMessage.contains('contraseña'))
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 12),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red.shade700, size: 16),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _errorMessage,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Mensaje de error general
            if (_errorMessage.isNotEmpty &&
                !_errorMessage.contains('correo') &&
                !_errorMessage.contains('contraseña') &&
                !_errorMessage.contains('email'))
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(maxWidth: 320),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.red.shade700, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
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
            // Login Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: 320),
                height: 40,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_email.text.isNotEmpty &&
                              _password.text.isNotEmpty) {
                            signIn();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF0067FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Iniciar sesión',
                          style: TextStyle(fontSize: 14),
                        ),
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
