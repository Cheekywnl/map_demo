import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:google_sign_in/google_sign_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  // Future<void> _signInWithGoogle() async {
  //   setState(() {
  //     _loading = true;
  //     _error = null;
  //   });
  //   try {
  //     final GoogleSignInAccount? googleUser = await GoogleSignIn.standard().signIn();
  //     if (googleUser == null) {
  //       setState(() => _loading = false);
  //       return; // User cancelled
  //     }
  //     final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
  //     final credential = GoogleAuthProvider.credential(
  //       accessToken: googleAuth.accessToken,
  //       idToken: googleAuth.idToken,
  //     );
  //     await FirebaseAuth.instance.signInWithCredential(credential);
  //     if (!mounted) return;
  //     Navigator.of(context).pushReplacementNamed('/map');
  //   } catch (e) {
  //     setState(() {
  //       _error = 'Sign in failed: $e';
  //       _loading = false;
  //     });
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Sign in to continue'),
                  const SizedBox(height: 24),
                  // ElevatedButton.icon(
                  //   icon: Image.asset('assets/google_logo.png', height: 24),
                  //   label: const Text('Sign in with Google'),
                  //   onPressed: _signInWithGoogle,
                  // ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ]
                ],
              ),
      ),
    );
  }
} 