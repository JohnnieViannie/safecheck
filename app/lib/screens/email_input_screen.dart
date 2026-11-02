import 'package:flutter/material.dart';
import 'package:safecheck/screens/email_code_screen.dart';
import 'package:safecheck/screens/forgot_password_screen.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/screens/onboarding_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/widgets/auth_screen_shell.dart';
import 'package:safecheck/widgets/auth_step_indicator.dart';
import 'package:safecheck/widgets/custom_button.dart';
import 'package:safecheck/widgets/input_field.dart';

enum AuthFlowMode { login, signUp }

class EmailInputScreen extends StatefulWidget {
  const EmailInputScreen({
    super.key,
    required this.skipIfLoggedIn,
    this.mode = AuthFlowMode.login,
  });

  final bool skipIfLoggedIn;
  final AuthFlowMode mode;

  @override
  State<EmailInputScreen> createState() => _EmailInputScreenState();
}

class _EmailInputScreenState extends State<EmailInputScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  bool get _isSignUp => widget.mode == AuthFlowMode.signUp;

  @override
  void initState() {
    super.initState();
    if (widget.skipIfLoggedIn) {
      _routeLoggedInUser();
    }
  }

  Future<void> _routeLoggedInUser() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      return;
    }
    final profile = await AuthService.instance.getUserProfile(user.uid);
    if (!mounted) {
      return;
    }
    if (profile != null && profile.onboardingCompleted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
    );
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email);
  }

  void _leaveScreen(VoidCallback navigate) {
    authDismissKeyboardAndRun(context, navigate);
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (!_isValidEmail(email)) {
      setState(
        () => _error = 'Enter a valid email address, e.g. you@example.com',
      );
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    await AuthService.instance.sendEmailCode(
      email: email,
      password: password,
      onCodeSent: (String verificationId) {
        if (!mounted) {
          return;
        }
        setState(() => _loading = false);
        _leaveScreen(() {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EmailCodeScreen(
                email: email,
                password: password,
                verificationId: verificationId,
                isSignUp: _isSignUp,
              ),
            ),
          );
        });
      },
      onError: (String message) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = message;
        });
      },
    );
  }

  void _goToForgotPassword() {
    _leaveScreen(() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ForgotPasswordScreen(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _passwordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenScaffold(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const AuthBrandHeader(),
            const SizedBox(height: 28),
            AuthHeadline(
              primary: _isSignUp ? 'Create your\n' : 'Log in with\n',
              accent: _isSignUp ? 'account.' : 'email.',
            ),
            const SizedBox(height: 14),
            AuthBodyText(
              text: _isSignUp
                  ? 'Create your SafeBangle account with email and password.'
                  : 'Enter your email and password to continue.',
            ),
            if (_isSignUp) ...<Widget>[
              const SizedBox(height: 20),
              const AuthStepIndicator(
                currentStep: 1,
                totalSteps: 3,
                brightOnDark: true,
              ),
            ],
            const SizedBox(height: 28),
            InputField(
              controller: _emailController,
              label: 'Email Address',
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continue(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'At least 6 characters',
                counterText: '',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.white54,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
            ),
            if (!_isSignUp) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _goToForgotPassword,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: AuthScreenColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 14),
              AuthErrorBanner(message: _error!),
            ],
            const SizedBox(height: 32),
            CustomButton(
              label: _isSignUp ? 'Continue  →' : 'Log in  →',
              backgroundColor: AuthScreenColors.accent,
              loading: _loading,
              onPressed: _continue,
            ),
            const SizedBox(height: 20),
            const AuthBodyText(
              text: 'SafeBangle staff create accounts. Contact us if you need one.',
            ),
          ],
        ),
      ),
    );
  }
}
