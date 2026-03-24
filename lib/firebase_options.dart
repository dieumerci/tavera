// firebase_options.dart — manually constructed from google-services.json +
// GoogleService-Info.plist. Equivalent to what `flutterfire configure` generates.
// Do NOT commit the google-services.json / GoogleService-Info.plist files to
// source control — these API keys are tied to this Firebase project.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web is not supported by Tavera.');
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS     => ios,
      _ => throw UnsupportedError(
          'Unsupported platform: $defaultTargetPlatform'),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:           'AIzaSyBdEz1dNpDJ88CrMm0jSq6xY0RSeKvidOU',
    appId:            '1:562519729615:android:151906f8b81490aabc9eba',
    messagingSenderId: '562519729615',
    projectId:        'tavera-5498a',
    storageBucket:    'tavera-5498a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:           'AIzaSyCjQbIiI6tDMeU2yFnbRdKFxhbvxd1wAK0',
    appId:            '1:562519729615:ios:d38bd3c965fc35d3bc9eba',
    messagingSenderId: '562519729615',
    projectId:        'tavera-5498a',
    storageBucket:    'tavera-5498a.firebasestorage.app',
    iosBundleId:      'com.tavera.tavera',
  );
}
