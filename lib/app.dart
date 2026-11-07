import 'dart:ui' show AppExitResponse;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/catppuccin.dart';
import 'core/theme.dart';
import 'data/app_state.dart';
import 'data/models.dart';
import 'l10n/strings.dart';
import 'player/desktop_playback.dart';
import 'ui/app_shell.dart';

/// A gentle text-size bump for desktop windows.
///
/// Desktop Material text sizes are tuned for a mouse at arm's length, but a
/// media centre is usually read from a sofa, and the rest of the app already
/// sizes media artwork for a distance. Scaling type instead of every custom
/// widget keeps the layout predictable; the multiplier stays small enough that
/// nothing wraps differently, and a user's own accessibility scale is applied
/// on top rather than replaced.
class _DesktopTextScaler extends TextScaler {
  _DesktopTextScaler(this.inner, this.factor);

  final TextScaler inner;
  final double factor;

  @override
  double scale(double fontSize) => inner.scale(fontSize * factor);

  @override
  double get textScaleFactor => inner.textScaleFactor * factor;

  // MediaQueryData compares its text scaler by value. Without this, a new
  // wrapper instance on every app rebuild would look like a scale change and
  // rebuild every MediaQuery-dependent widget (the AppState ticker alone
  // rebuilds the app every 30 seconds).
  @override
  bool operator ==(Object other) =>
      other is _DesktopTextScaler &&
      other.factor == factor &&
      other.inner == inner;

  @override
  int get hashCode => Object.hash(inner, factor);
}

double _desktopTextScale(Size size) {
  if (kIsWeb) {
    return 1;
  }
  final desktop = switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows =>
      true,
    _ => false,
  };
  if (!desktop) {
    return 1;
  }
  if (size.width >= 1400) {
    return 1.1;
  }
  if (size.width >= 1000) {
    return 1.07;
  }
  return 1.03;
}

class MojacScrollBehavior extends MaterialScrollBehavior {
  const MojacScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class MojacApp extends StatefulWidget {
  const MojacApp({super.key});

  @override
  State<MojacApp> createState() => _MojacAppState();
}

class _MojacAppState extends State<MojacApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  /// Quit the system mpv when Mojac closes. Otherwise mpv keeps the channel
  /// open in an orphan window and the server keeps transcoding for a viewer
  /// that is gone.
  Future<AppExitResponse> _onExitRequested() async {
    await DesktopPlayback.instance.stop();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    final family = settings.themeFamily;

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final theme = buildMojacTheme(
          family: family,
          accent: settings.accent,
          brightness: Brightness.light,
          dynamicScheme: family == ThemeFamily.system ? lightDynamic : null,
        );
        final darkTheme = buildMojacTheme(
          family: family,
          accent: settings.accent,
          brightness: Brightness.dark,
          dynamicScheme: family == ThemeFamily.system ? darkDynamic : null,
        );

        final languageCode = settings.language.localeCode;
        return MaterialApp(
          title: 'Mojac',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: darkTheme,
          themeMode: family == ThemeFamily.system
              ? ThemeMode.system
              : (family.isDark! ? ThemeMode.dark : ThemeMode.light),
          themeAnimationDuration: const Duration(milliseconds: 220),
          locale: languageCode == null ? null : Locale(languageCode),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scrollBehavior: const MojacScrollBehavior(),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final desktopScale = _desktopTextScale(media.size);
            return MediaQuery(
              data: media.copyWith(
                alwaysUse24HourFormat: settings.use24HourTime,
                textScaler: desktopScale == 1
                    ? media.textScaler
                    : _DesktopTextScaler(media.textScaler, desktopScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AppShell(),
        );
      },
    );
  }
}
