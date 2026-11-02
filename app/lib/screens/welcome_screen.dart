import 'package:flutter/material.dart';
import 'package:safecheck/screens/login_screen.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/auth_screen_shell.dart';
import 'package:safecheck/widgets/custom_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const Color _background = AuthScreenColors.background;
  static const Color _cardBackground = AuthScreenColors.card;
  static const Color _accent = AuthScreenColors.accent;

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
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
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

  void _onExistingAccount() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme.copyWith(
        scaffoldBackgroundColor: _background,
      ),
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: SlideTransition(
              position: _slideUp,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const AuthBrandHeader(),
                    const SizedBox(height: 28),
                    _buildHeadline(),
                    const SizedBox(height: 14),
                    _buildIntro(),
                    const SizedBox(height: 28),
                    _FeatureCard(
                      background: _cardBackground,
                      icon: Icons.alarm_rounded,
                      iconColor: const Color(0xFFF472B6),
                      title: 'Daily check-in, your way.',
                      description:
                          'Set your own schedule — daily, weekly, or monthly.',
                    ),
                    const SizedBox(height: 12),
                    _FeatureCard(
                      background: _cardBackground,
                      icon: Icons.notifications_off_rounded,
                      iconColor: const Color(0xFFFBBF24),
                      title: 'Silent protection.',
                      description:
                          'Runs in the background. Only acts when you don\'t respond.',
                    ),
                    const SizedBox(height: 12),
                    _FeatureCard(
                      background: _cardBackground,
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFFF472B6),
                      title: 'Alerts your people.',
                      description:
                          'SMS, WhatsApp, email — with your last known location.',
                    ),
                    const SizedBox(height: 32),
                    CustomButton(
                      label: 'Log in  →',
                      backgroundColor: _accent,
                      onPressed: _onExistingAccount,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeadline() {
    return RichText(
      text: const TextSpan(
        style: TextStyle(
          fontSize: 34,
          height: 1.15,
          fontWeight: FontWeight.w700,
          fontFamily: 'Georgia',
        ),
        children: <TextSpan>[
          TextSpan(
            text: 'Someone\'s Always\n',
            style: TextStyle(color: Colors.white),
          ),
          TextSpan(
            text: 'Checking On You.',
            style: TextStyle(color: _accent),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Text(
      'SafeCheck quietly monitors that you\'re okay. If you ever can\'t respond, it acts on your behalf — alerting the people who care about you.',
      style: TextStyle(
        fontSize: 15,
        height: 1.5,
        color: Colors.white.withValues(alpha: 0.62),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.background,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final Color background;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
