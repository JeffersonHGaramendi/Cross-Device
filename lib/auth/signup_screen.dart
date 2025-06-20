import 'dart:developer';

import 'package:crossdevice/auth/login_screen.dart';
import 'package:crossdevice/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _errorMessage = '';

  // Función para mostrar mensajes de error personalizados
  String _getErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'email-already-in-use':
        return 'Ya existe una cuenta con este correo electrónico.';
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'weak-password':
        return 'La contraseña es muy débil. Debe tener al menos 6 caracteres.';
      case 'operation-not-allowed':
        return 'El registro con correo y contraseña no está habilitado.';
      case 'network-request-failed':
        return 'Error de conexión. Verifica tu internet.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      default:
        return 'Ha ocurrido un error durante el registro. Intenta nuevamente.';
    }
  }

  // Función para validar el formato del email
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // Función para validar el nombre
  bool _isValidName(String name) {
    return name.trim().length >= 2 &&
        RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$').hasMatch(name.trim());
  }

  _signup() async {
    // Limpiar mensaje de error anterior
    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    // Validaciones básicas
    if (_name.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Por favor ingrese su nombre completo.';
        _isLoading = false;
      });
      return;
    }

    if (!_isValidName(_name.text)) {
      setState(() {
        _errorMessage =
            'El nombre debe tener al menos 2 caracteres y solo contener letras.';
        _isLoading = false;
      });
      return;
    }

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
        _errorMessage = 'Por favor ingrese una contraseña.';
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
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      // Actualizar el perfil del usuario con el nombre
      await userCredential.user?.updateDisplayName(_name.text.trim());

      log('User Created Successfully: ${userCredential.user?.email}');

      // Limpiar campos y navegar
      _name.clear();
      _email.clear();
      _password.clear();

      if (mounted) {
        homeScreenFromSignUp(context);
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

  loginScreenFromSignUp(BuildContext context) => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );

  homeScreenFromSignUp(BuildContext context) => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => WifiSyncHome()),
      );

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            children: [
              const Spacer(),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  child: Text("Signup",
                      style:
                          TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(height: 50),

              // Name Input
              Container(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 56,
                      child: TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Enter Name',
                          labelText: 'Name',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    // Mensaje de error específico para nombre
                    if (_errorMessage.isNotEmpty &&
                        _errorMessage.contains('nombre'))
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
              const SizedBox(height: 20),

              // Email Input
              Container(
                width: double.infinity,
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
              const SizedBox(height: 20),

              // Password Input
              Container(
                width: double.infinity,
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

              // Mensaje de error general
              if (_errorMessage.isNotEmpty &&
                  !_errorMessage.contains('nombre') &&
                  !_errorMessage.contains('correo') &&
                  !_errorMessage.contains('contraseña') &&
                  !_errorMessage.contains('email'))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(
                    width: double.infinity,
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

              const SizedBox(height: 30),

              // Sign Up Button
              Container(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_email.text.isNotEmpty &&
                              _password.text.isNotEmpty &&
                              _name.text.isNotEmpty) {
                            _signup();
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
                          'Crear cuenta',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // Login Link
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Already have an account? "),
                InkWell(
                  onTap: () => loginScreenFromSignUp(context),
                  child: const Text("Login",
                      style: TextStyle(
                        color: Color(0xFF0067FF),
                        fontWeight: FontWeight.w500,
                      )),
                )
              ]),
              const Spacer()
            ],
          ),
        ),
      ),
    );
  }
}
