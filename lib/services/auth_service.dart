import 'package:firebase_auth/firebase_auth.dart';
// import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Stream for auth state
  Stream<User?> get userChanges => _auth.authStateChanges();

  // Google Sign-In
  // Future<User?> signInWithGoogle() async {
  //   // TODO: Implement Google Sign-In logic
  //   return null;
  // }

  // Sign out
  Future<void> signOut() async {
    // TODO: Implement sign out logic
  }
} 