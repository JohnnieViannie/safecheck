import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/utils/auth_navigation.dart';
import 'package:safecheck/widgets/auth_screen_shell.dart';
import 'package:safecheck/widgets/auth_step_indicator.dart';
import 'package:safecheck/widgets/custom_button.dart';

class EmailCodeScreen extends StatefulWidget {
  const EmailCodeScreen({
    super.key,
    required this.email,
    required this.password,
    required this.verificationId,
    this.isSignUp = false,
  });

  final String email;
  final String password;
  final String verificationId;
  final bool isSignUp;

  @override
  State<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends State<EmailCodeScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  String? _error;
  bool _resending = false;
  late String _verificationId;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  String get _otpValue => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_otpValue.length == 6) {
      _verifyCode();
    }
  }

  void _onKeyDown(int index, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    final String otp = _otpValue;
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    await AuthService.instance.verifyEmailCode(
      verificationId: _verificationId,
      email: widget.email,
      password: widget.password,
      code: otp,
      onSuccess: (profile) async {
        if (!mounted) {
          return;
        }
        await AuthNavigation.routeAfterAuth(context, profile);
      },
      onError: (errorMessage) {
        if (!mounted) {
          return;
        }
        setState(() => _error = errorMessage);
      },
    );

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    await AuthService.instance.sendEmailCode(
      email: widget.email,
      password: widget.password,
      onCodeSent: (String verificationId) {
        if (!mounted) return;
        setState(() {
          _resending = false;
          _verificationId = verificationId;
          _error = null;
          for (final TextEditingController controller in _controllers) {
            controller.clear();
          }
        });
        _focusNodes[0].requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Verification code resent!'),
            backgroundColor: AuthScreenColors.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _resending = false;
          _error = msg;
        });
      },
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenScaffold(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.isSignUp) ...<Widget>[
              const AuthStepIndicator(
                currentStep: 2,
                totalSteps: 3,
                brightOnDark: true,
              ),
              const SizedBox(height: 24),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AuthScreenColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                size: 32,
                color: AuthScreenColors.accent,
              ),
            ),
            const SizedBox(height: 24),
            AuthHeadline(
              primary: widget.isSignUp ? 'Check your\n' : 'Check your\n',
              accent: 'inbox.',
            ),
            const SizedBox(height: 14),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.62),
                ),
                children: <InlineSpan>[
                  const TextSpan(text: 'We sent a 6-digit code to '),
                  TextSpan(
                    text: widget.email,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List<Widget>.generate(6, (int index) {
                return SizedBox(
                  width: 48,
                  height: 56,
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (KeyEvent event) => _onKeyDown(index, event),
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AuthScreenColors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AuthScreenColors.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AuthScreenColors.accent,
                            width: 2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      onChanged: (String value) => _onDigitChanged(index, value),
                    ),
                  ),
                );
              }),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              AuthErrorBanner(message: _error!),
            ],
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: _resending ? null : _resendCode,
                child: _resending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AuthScreenColors.accent,
                        ),
                      )
                    : const Text(
                        'Didn\'t get it? Resend code',
                        style: TextStyle(
                          color: AuthScreenColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            CustomButton(
              label: 'Verify Code  →',
              backgroundColor: AuthScreenColors.accent,
              loading: _loading,
              onPressed: _verifyCode,
            ),
          ],
        ),
      ),
    );
  }
}
