import 'dart:async';

import 'package:flutter/material.dart';
import 'package:safecheck/config/app_config.dart';
import 'package:safecheck/screens/email_input_screen.dart';
import 'package:safecheck/screens/phone_input_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/biometric_service.dart';
import 'package:safecheck/utils/app_log.dart';
import 'package:safecheck/utils/auth_navigation.dart';
import 'package:safecheck/widgets/auth_screen_shell.dart';
import 'package:safecheck/widgets/custom_button.dart';
import 'package:safecheck/widgets/google_logo.dart';
import 'package:safecheck/widgets/social_sign_in_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _googleLoading = false;
  bool _biometricLoading = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBiometricAvailability());
  }

  Future<void> _loadBiometricAvailability() async {
    final bool hasStored = await BiometricService.instance.hasStoredLogin();
    final bool canUse = await BiometricService.instance.canUnlockApp();
    if (!mounted) return;
    setState(() => _biometricAvailable = hasStored && canUse);
  }

  Future<void> _onGoogleLogin() async {
    setState(() => _googleLoading = true);
    await AuthService.instance.signInWithGoogle(
      onSuccess: (user) async {
        if (!mounted) return;
        await AuthNavigation.routeAfterAuth(context, user);
      },
      onError: (msg) {
        if (!mounted) return;
        if (msg.toLowerCase().contains('cancel')) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        appLog(msg);
      },
    );
    if (mounted) setState(() => _googleLoading = false);
  }

  Future<void> _onBiometricLogin() async {
    setState(() => _biometricLoading = true);
    await AuthService.instance.signInWithBiometrics(
      onSuccess: (user) async {
        if (!mounted) return;
        await AuthNavigation.routeAfterAuth(context, user);
      },
      onError: (String msg) {
        if (!mounted) return;
        if (msg.toLowerCase().contains('cancel')) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        appLog(msg);
      },
    );
    if (mounted) setState(() => _biometricLoading = false);
  }

  void _onContinueWithPhone() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PhoneInputScreen(skipIfLoggedIn: false),
      ),
    );
  }

  void _onContinueWithEmail() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const EmailInputScreen(
          skipIfLoggedIn: false,
          mode: AuthFlowMode.login,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenScaffold(
      showBack: false,
      trailing: _biometricAvailable
          ? IconButton(
              onPressed: _biometricLoading ? null : _onBiometricLogin,
              tooltip: 'Continue with Face ID / Fingerprint',
              icon: _biometricLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fingerprint_rounded),
              color: Colors.white70,
              style: IconButton.styleFrom(
                backgroundColor: AuthScreenColors.card,
                minimumSize: const Size(40, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AuthBrandHeader(),
          const SizedBox(height: 28),
          const AuthHeadline(
            primary: 'Welcome\n',
            accent: 'back.',
          ),
          const SizedBox(height: 14),
          const AuthBodyText(
            text:
                'Log in to access your safety check-ins and guardian alerts.',
          ),
          const SizedBox(height: 32),
          if (AppConfig.enableGoogleSignIn) ...<Widget>[
            SocialSignInButton(
              label: 'Log in with Google',
              loading: _googleLoading,
              backgroundColor: AuthScreenColors.card,
              foregroundColor: Colors.white,
              borderColor: Colors.white.withValues(alpha: 0.12),
              icon: const GoogleLogo(size: 20),
              onPressed: _onGoogleLogin,
            ),
            const SizedBox(height: 12),
          ],
          CustomButton(
            label: 'Continue with Phone  →',
            backgroundColor: AuthScreenColors.accent,
            onPressed: _onContinueWithPhone,
          ),
          const SizedBox(height: 12),
          AuthSecondaryButton(
            label: 'Continue with Email',
            onPressed: _onContinueWithEmail,
          ),
          const SizedBox(height: 16),
          const AuthBodyText(
            text: 'SafeBangle staff create accounts. Contact us if you need one.',
          ),
        ],
      ),
    );
  }
}
