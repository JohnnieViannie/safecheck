// Generated from google-services.json (project safecheck-c4fa6).
// Override at build time with --dart-define if needed.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const String _defaultApiKey = 'AIzaSyDRrE8UjiAImAYLnwX1QjMcRaDvKDGbnfA';
  static const String _defaultAppId =
      '1:780122444136:android:d0c9d2769084feb5fd46dd';
  static const String _defaultMessagingSenderId = '780122444136';
  static const String _defaultProjectId = 'safecheck-c4fa6';

  static bool get isConfigured {
    return currentPlatform.apiKey.isNotEmpty &&
        currentPlatform.appId.isNotEmpty &&
        currentPlatform.projectId.isNotEmpty;
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase push is not configured for web in SafeCheck.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Firebase push is not supported on this platform.');
    }
  }

  static FirebaseOptions get android => FirebaseOptions(
        apiKey: const String.fromEnvironment(
          'FIREBASE_API_KEY',
          defaultValue: _defaultApiKey,
        ),
        appId: const String.fromEnvironment(
          'FIREBASE_APP_ID',
          defaultValue: _defaultAppId,
        ),
        messagingSenderId: const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
          defaultValue: _defaultMessagingSenderId,
        ),
        projectId: const String.fromEnvironment(
          'FIREBASE_PROJECT_ID',
          defaultValue: _defaultProjectId,
        ),
      );

  static FirebaseOptions get ios => FirebaseOptions(
        apiKey: const String.fromEnvironment(
          'FIREBASE_API_KEY',
          defaultValue: _defaultApiKey,
        ),
        appId: const String.fromEnvironment(
          'FIREBASE_APP_ID',
          defaultValue: _defaultAppId,
        ),
        messagingSenderId: const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
          defaultValue: _defaultMessagingSenderId,
        ),
        projectId: const String.fromEnvironment(
          'FIREBASE_PROJECT_ID',
          defaultValue: _defaultProjectId,
        ),
        iosBundleId: const String.fromEnvironment(
          'FIREBASE_IOS_BUNDLE_ID',
          defaultValue: 'com.safecheck.app',
        ),
      );
}
