import 'package:flutter/material.dart';
import 'package:safecheck/screens/reset_password_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/widgets/auth_screen_shell.dart';
import 'package:safecheck/widgets/custom_button.dart';
import 'package:safecheck/widgets/input_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email);
  }

  Future<void> _sendResetCode() async {
    FocusScope.of(context).unfocus();

    final String email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    await AuthService.instance.sendPasswordResetCode(
      email: email,
      onCodeSent: (String verificationId) {
        if (!mounted) return;
        setState(() => _loading = false);
        authDismissKeyboardAndRun(context, () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ResetPasswordScreen(
                email: email,
                verificationId: verificationId,
              ),
            ),
          );
        });
      },
      onError: (String message) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = message;
        });
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AuthScreenColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.lock_reset_outlined,
              size: 32,
              color: AuthScreenColors.accent,
            ),
          ),
          const SizedBox(height: 24),
          const AuthHeadline(
            primary: 'Reset your\n',
            accent: 'password.',
          ),
          const SizedBox(height: 14),
          const AuthBodyText(
            text:
                'Enter the email for your account. We will send a 6-digit code to reset your password.',
          ),
          const SizedBox(height: 28),
          InputField(
            controller: _emailController,
            label: 'Email Address',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            AuthErrorBanner(message: _error!),
          ],
          const SizedBox(height: 32),
          CustomButton(
            label: 'Send reset code  →',
            backgroundColor: AuthScreenColors.accent,
            loading: _loading,
            onPressed: _sendResetCode,
          ),
        ],
      ),
    );
  }
}
