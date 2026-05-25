import 'package:flutter/material.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/screens/onboarding_screen.dart';
import 'package:safecheck/screens/otp_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/widgets/custom_button.dart';
import 'package:safecheck/widgets/input_field.dart';

class PhoneInputScreen extends StatefulWidget {
  const PhoneInputScreen({super.key, required this.skipIfLoggedIn});

  final bool skipIfLoggedIn;

  @override
  State<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _loading = false;
  String? _error;

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

  Future<void> _sendCode() async {
    final String phone = _phoneController.text.trim();
    if (!phone.startsWith('+') || phone.length < 8) {
      setState(() => _error = 'Enter a valid phone number with country code, e.g. +14155550123');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    await AuthService.instance.sendOtp(
      phoneNumber: phone,
      onCodeSent: (String verificationId) {
        if (!mounted) {
          return;
        }
        setState(() => _loading = false);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OtpScreen(
              phoneNumber: phone,
              verificationId: verificationId,
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

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phone Verification')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 20),
              const Text('Enter your phone number', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              InputField(
                controller: _phoneController,
                label: 'Phone Number',
                hint: '+14155550123',
                keyboardType: TextInputType.phone,
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const Spacer(),
              CustomButton(label: 'Send Code', loading: _loading, onPressed: _sendCode),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
