import 'package:flutter/material.dart';
import 'package:safecheck/screens/create_account_screen.dart';
import 'package:safecheck/screens/email_code_screen.dart';
import 'package:safecheck/screens/forgot_password_screen.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/screens/onboarding_screen.dart';
import 'package:safecheck/screens/welcome_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/app_logo.dart';
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

class _EmailInputScreenState extends State<EmailInputScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  bool get _isSignUp => widget.mode == AuthFlowMode.signUp;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

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

  void _goToCreateAccount() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CreateAccountScreen(),
      ),
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignUp ? 'Create account' : 'Log in'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 12),
                  const AppLogo(height: 56),
                  const SizedBox(height: 20),
                  if (_isSignUp) ...<Widget>[
                    const AuthStepIndicator(currentStep: 1, totalSteps: 3),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    _isSignUp ? 'Create your account' : 'Welcome back',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp
                        ? 'Create your SafeBangle account with email and password.'
                        : 'Enter your email and password to access your account.',
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.4,
                    ),
                  ),
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
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'At least 6 characters',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: isDark ? Colors.white54 : Colors.black45,
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
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  CustomButton(
                    label: _isSignUp ? 'Continue' : 'Log in',
                    loading: _loading,
                    onPressed: _continue,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          _isSignUp
                              ? 'Already have an account? '
                              : 'Don\'t have an account? ',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white38 : Colors.grey.shade600,
                          ),
                        ),
                        TextButton(
                          onPressed: _isSignUp ? _goToLogin : _goToCreateAccount,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(_isSignUp ? 'Log in' : 'Create account'),
                        ),
                      ],
                    ),
                  ),
                  if (MediaQuery.of(context).padding.bottom > 0)
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
