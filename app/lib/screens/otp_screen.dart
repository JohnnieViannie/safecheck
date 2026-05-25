import 'package:flutter/material.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/screens/onboarding_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/widgets/custom_button.dart';
import 'package:safecheck/widgets/input_field.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  final String phoneNumber;
  final String verificationId;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _verifyCode() async {
    final String otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    await AuthService.instance.verifyOtp(
      verificationId: widget.verificationId,
      phoneNumber: widget.phoneNumber,
      smsCode: otp,
      onSuccess: (profile) {
        if (!mounted) {
          return;
        }
        if (profile.onboardingCompleted) {
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

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Code')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 20),
              Text('Enter the code sent to ${widget.phoneNumber}', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              InputField(
                controller: _otpController,
                label: '6-digit OTP',
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const Spacer(),
              CustomButton(label: 'Verify Code', loading: _loading, onPressed: _verifyCode),
            ],
          ),
        ),
      ),
    );
  }
}
