import 'package:flutter/foundation.dart';

/// Debug-only logging. No-op in release builds.
void appLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
