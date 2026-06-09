import 'package:flutter/material.dart';
import 'package:safecheck/config/app_config.dart';
import 'package:safecheck/screens/email_input_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/utils/app_log.dart';
import 'package:safecheck/utils/auth_navigation.dart';
import 'package:safecheck/widgets/app_logo.dart';
import 'package:safecheck/widgets/auth_step_indicator.dart';
import 'package:safecheck/widgets/custom_button.dart';
import 'package:safecheck/widgets/social_sign_in_button.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen>
    with SingleTickerProviderStateMixin {
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

  Future<void> _onGoogleSignUp() async {
    setState(() => _googleLoading = true);
    await AuthService.instance.signInWithGoogle(
      onSuccess: (user) async {
        if (!mounted) return;
        await AuthNavigation.routeAfterAuth(context, user);
      },
      onError: (msg) {
        if (!mounted) return;
        if (msg.toLowerCase().contains('cancelled')) {
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

  Future<void> _onAppleSignUp() async {
    setState(() => _appleLoading = true);
    await AuthService.instance.socialSignIn(
      provider: 'apple',
      onSuccess: (user) async {
        if (!mounted) return;
        await AuthNavigation.routeAfterAuth(context, user);
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      },
    );
    if (mounted) setState(() => _appleLoading = false);
  }

  void _onEmailSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const EmailInputScreen(
          skipIfLoggedIn: false,
          mode: AuthFlowMode.signUp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: SlideTransition(
            position: _slideUp,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  padding: AppTheme.screenPadding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const AppLogo(height: 56),
                          const SizedBox(height: 20),
                          const AuthStepIndicator(currentStep: 1, totalSteps: 3),
                          const SizedBox(height: 24),
                          Text(
                            'Get started with SafeBangle',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create your account to set up scheduled safety check-ins and guardian alerts.',
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? Colors.white60 : Colors.black54,
                              height: 1.4,
                            ),
                          ),
                          const Spacer(),
                          if (AppConfig.enableSocialSignIn) ...<Widget>[
                            if (AppConfig.enableGoogleSignIn) ...<Widget>[
                              SocialSignInButton(
                                label: 'Sign up with Google',
                                loading: _googleLoading,
                                icon: const Icon(
                                  Icons.g_mobiledata,
                                  size: 28,
                                  color: Colors.red,
                                ),
                                onPressed: _onGoogleSignUp,
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (AppConfig.enableAppleSignIn) ...<Widget>[
                              SocialSignInButton(
                                label: 'Sign up with Apple',
                                loading: _appleLoading,
                                icon: Icon(
                                  Icons.apple,
                                  size: 24,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                onPressed: _onAppleSignUp,
                              ),
                              const SizedBox(height: 14),
                            ],
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Divider(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
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
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ],
                          CustomButton(
                            label: 'Sign up with Email',
                            onPressed: _onEmailSignUp,
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                Text(
                                  'Already have an account? ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade600,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Log in'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
