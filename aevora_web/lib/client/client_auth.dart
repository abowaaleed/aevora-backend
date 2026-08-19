import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_config.dart';

/// طبقة المصادقة: دخول بحساب Google عبر Firebase Auth.
Future<void> initFirebase() async {
  if (!isFirebaseConfigured) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: FirebaseConfig.apiKey,
        authDomain: FirebaseConfig.authDomain,
        projectId: FirebaseConfig.projectId,
        storageBucket: FirebaseConfig.storageBucket,
        messagingSenderId: FirebaseConfig.messagingSenderId,
        appId: FirebaseConfig.appId,
      ),
    );
  }
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    await getGoogleRedirectResult();
  }
}

bool get isAuthEnabled => isFirebaseConfigured;

bool get isSignedIn =>
    isAuthEnabled && FirebaseAuth.instance.currentUser != null;

String? get currentUserId => isSignedIn ? FirebaseAuth.instance.currentUser!.uid : null;

String? get currentEmail => isSignedIn ? FirebaseAuth.instance.currentUser!.email : null;

String? get currentDisplayName =>
    isSignedIn ? FirebaseAuth.instance.currentUser!.displayName : null;

Stream<User?> authStateStream() {
  if (!isAuthEnabled) return const Stream.empty();
  return FirebaseAuth.instance.authStateChanges();
}

/// تسجيل الدخول بحساب Google.
Future<User?> signInWithGoogle() async {
  if (!isAuthEnabled) return null;
  
  if (kIsWeb) {
    final provider = GoogleAuthProvider();
    final cred = await FirebaseAuth.instance.signInWithPopup(provider);
    return cred.user;
  } else {
    // دعم الدخول على الأندرويد والايفون
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
    return userCredential.user;
  }
}

Future<void> signInWithGoogleRedirect() async {
  if (!isAuthEnabled || !kIsWeb) return;
  final provider = GoogleAuthProvider();
  await FirebaseAuth.instance.signInWithRedirect(provider);
}

Future<void> getGoogleRedirectResult() async {
  if (!isAuthEnabled || !kIsWeb) return;
  try {
    await FirebaseAuth.instance.getRedirectResult();
  } catch (_) {}
}

Future<void> signOut() async {
  if (isAuthEnabled && Firebase.apps.isNotEmpty) {
    if (!kIsWeb) {
      await GoogleSignIn().signOut();
    }
    await FirebaseAuth.instance.signOut();
  }
}
