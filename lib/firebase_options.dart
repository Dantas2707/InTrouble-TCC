import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC4RmrCluQDaFV2qI3rZEeLzzCShHrlOAY',
    appId: '1:171463482158:web:4f0b6e5d16d07cd07038bf',
    messagingSenderId: '171463482158',
    projectId: 'crud-6417b',
    authDomain: 'crud-6417b.firebaseapp.com',
    storageBucket: 'crud-6417b.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyApHDGkt7hrxXY2Bv_0LPmPTVtSdlyR29E',
    appId: '1:171463482158:android:0cc6c7e5892da9457038bf',
    messagingSenderId: '171463482158',
    projectId: 'crud-6417b',
    storageBucket: 'crud-6417b.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyC4RmrCluQDaFV2qI3rZEeLzzCShHrlOAY',
    appId: '1:171463482158:web:fb164fc505a76cf87038bf',
    messagingSenderId: '171463482158',
    projectId: 'crud-6417b',
    authDomain: 'crud-6417b.firebaseapp.com',
    storageBucket: 'crud-6417b.firebasestorage.app',
  );

}