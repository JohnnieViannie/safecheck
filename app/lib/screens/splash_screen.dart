import 'dart:async';

import 'package:flutter/material.dart';
import 'package:safecheck/models/user_model.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/screens/onboarding_screen.dart';
import 'package:safecheck/screens/welcome_screen.dart';
import 'package:safecheck/services/app_bootstrap.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/app_logo.dart';

/// Branded splash — routes to home or welcome as soon as session is known.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _minDisplay = Duration(milliseconds: 450);

  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<double> _ringScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
      ),
    );
    _ringScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
    unawaited(_routeWhenReady());
  }

  Future<void> _routeWhenReady() async {
    final Stopwatch timer = Stopwatch()..start();
    final bool loggedIn = AuthService.instance.isLoggedIn;

    AppBootstrap.startDeferredInit(loggedIn: loggedIn);

    final int remaining = _minDisplay.inMilliseconds - timer.elapsedMilliseconds;
    if (remaining > 0) {
      await Future<void>.delayed(Duration(milliseconds: remaining));
    }

    if (!mounted) {
      return;
    }

    final Widget destination;
    if (loggedIn) {
      final UserModel? user = await AuthService.instance.resolveSessionUser();
      final UserModel? profile = user != null
          ? await AuthService.instance.getUserProfile(user.uid)
          : null;
      if (!mounted) {
        return;
      }
      final bool onboardingDone = profile?.onboardingCompleted ?? false;
      destination = onboardingDone
          ? const HomeScreen()
          : const OnboardingScreen();
    } else {
      destination = const WelcomeScreen();
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushReplacement<void, void>(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? <Color>[
                    const Color(0xFF0D1B24),
                    const Color(0xFF142A35),
                    AppTheme.primary.withValues(alpha: 0.35),
                  ]
                : <Color>[
                    const Color(0xFFE8F4F8),
                    const Color(0xFFF8FAFC),
                    AppTheme.primary.withValues(alpha: 0.12),
                  ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 128,
                      height: 128,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          Transform.scale(
                            scale: _ringScale.value,
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primary.withValues(
                                    alpha: isDark ? 0.35 : 0.2,
                                  ),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: _logoOpacity.value,
                            child: Transform.scale(
                              scale: _logoScale.value,
                              child: const AppLogo(
                                height: 60,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Opacity(
                      opacity: _textOpacity.value,
                      child: Column(
                        children: <Widget>[
                          Text(
                            'SafeCheck',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your safety companion',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
