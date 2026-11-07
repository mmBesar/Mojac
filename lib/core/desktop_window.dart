import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Minimal bridge to the real OS window.
///
/// The built-in player's fullscreen button is the only caller. On Android
/// `SystemChrome` already does the right thing, so this stays a no-op there.
/// On a desktop the app window is a normal decorated window, and merely hiding
/// the Flutter UI chrome (the old behaviour) left the title bar, the
/// taskbar/dock and the desktop visible: not fullscreen at all. Asking the
/// window manager instead gives real fullscreen, and leaving it restores the
/// previous window state.
///
/// Every call is guarded: the plugin needs a real desktop session and a
/// loaded native library, and a missing window must not crash playback.
class DesktopWindow {
  DesktopWindow._();

  static final DesktopWindow instance = DesktopWindow._();

  /// Whether Mojac can drive the OS window on this platform.
  static bool get isSupported =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  bool? _lastRequested;

  /// Enters or leaves real fullscreen. Returns true when the window manager
  /// accepted the request, so the caller knows whether the platform-specific
  /// fallbacks are still needed.
  Future<bool> setFullscreen(bool fullscreen) async {
    if (!isSupported) {
      return false;
    }
    if (_lastRequested == fullscreen) {
      return true;
    }
    final window = await _currentWindow();
    if (window == null) {
      return false;
    }
    try {
      window.isFullScreen = fullscreen;
      _lastRequested = fullscreen;
      return true;
    } catch (error) {
      debugPrint('Could not set desktop fullscreen: $error');
      return false;
    }
  }

  /// Asks for the window a few times: on the very first frame the engine may
  /// not have attached its native window yet.
  Future<Window?> _currentWindow() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final window = WindowManager.instance.getCurrent();
        if (window != null) {
          return window;
        }
      } catch (error) {
        debugPrint('Desktop window is unavailable: $error');
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return null;
  }
}
