import 'package:flutter/material.dart';
import 'package:safecheck/screens/email_input_screen.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/screens/onboarding_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/permissions_service.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/app_logo.dart';
import 'package:safecheck/widgets/custom_button.dart';
import 'package:safecheck/widgets/social_sign_in_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;

  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
          ),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _onContinueWithEmail() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;
    setState(() => _isLoading = false);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const EmailInputScreen(skipIfLoggedIn: false),
      ),
    );
  }

  Future<void> _onGoogleSignIn() async {
    setState(() => _googleLoading = true);
    await AuthService.instance.signInWithGoogle(
      onSuccess: (user) async {
        await PermissionsService.instance.requestPostSignInPermissions();
        if (!mounted) return;
        if (user.onboardingCompleted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
            (_) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
            (_) => false,
          );
        }
      },
      onError: (msg) {
        if (!mounted) return;
        if (msg.toLowerCase().contains('cancelled')) {
          // User dismissed the account picker; do not show noisy error UI.
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        print(msg);
      },
    );
    if (mounted) setState(() => _googleLoading = false);
  }

  Future<void> _onAppleSignIn() async {
    setState(() => _appleLoading = true);
    // TODO: Integrate real Apple Sign-In (sign_in_with_apple package).
    await AuthService.instance.socialSignIn(
      provider: 'apple',
      onSuccess: (user) async {
        await PermissionsService.instance.requestPostSignInPermissions();
        if (!mounted) return;
        if (user.onboardingCompleted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
            (_) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
            (_) => false,
          );
        }
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
    if (mounted) setState(() => _appleLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: SlideTransition(
            position: _slideUp,
            child: Padding(
              padding: AppTheme.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Spacer(flex: 2),

                  const AppLogo(height: 56),
                  const SizedBox(height: 28),

                  // Headline
                  Text(
                    'Scheduled safety calls.\nReal guardian alerts.',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      height: 1.15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Set your check-in time. If we do not hear "I am fine," SafeBangle retries your call and alerts your next of kin with your last location.',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.4,
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Email sign-in (primary)
                  CustomButton(
                    label: 'Continue with Email',
                    onPressed: _onContinueWithEmail,
                    loading: _isLoading,
                  ),
                  const SizedBox(height: 14),

                  // Divider
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'or',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Google sign-in
                  SocialSignInButton(
                    label: 'Continue with Google',
                    loading: _googleLoading,
                    icon: const Icon(
                      Icons.g_mobiledata,
                      size: 28,
                      color: Colors.red,
                    ),
                    onPressed: _onGoogleSignIn,
                  ),
                  const SizedBox(height: 10),

                  // Apple sign-in
                  SocialSignInButton(
                    label: 'Continue with Apple',
                    loading: _appleLoading,
                    icon: Icon(
                      Icons.apple,
                      size: 24,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    onPressed: _onAppleSignIn,
                  ),

                  const SizedBox(height: 20),

                  // Terms text
                  Center(
                    child: Text(
                      'By continuing you agree to our Terms & Privacy Policy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white30 : Colors.grey.shade500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
