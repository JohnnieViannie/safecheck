import 'package:flutter/material.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/app_logo.dart';

class AuthScreenColors {
  AuthScreenColors._();

  static const Color background = Color(0xFF0A192F);
  static const Color card = Color(0xFF112240);
  static const Color accent = Color(0xFF14B8A6);
}

/// Dismisses the keyboard, optionally waits, then runs [action].
void authDismissKeyboardAndRun(
  BuildContext context,
  VoidCallback action, {
  Duration delay = const Duration(milliseconds: 200),
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  Future<void>.delayed(delay, () {
    if (context.mounted) {
      action();
    }
  });
}

EdgeInsets _authScrollPadding(
  BuildContext context,
  EdgeInsetsGeometry padding,
) {
  final EdgeInsets base = padding.resolve(Directionality.of(context));
  return base.copyWith(
    bottom: base.bottom + MediaQuery.viewInsetsOf(context).bottom,
  );
}

ThemeData authScreenTheme() {
  return AppTheme.darkTheme.copyWith(
    scaffoldBackgroundColor: AuthScreenColors.background,
    colorScheme: AppTheme.darkTheme.colorScheme.copyWith(
      primary: AuthScreenColors.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AuthScreenColors.card,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AuthScreenColors.accent, width: 1.5),
      ),
    ),
  );
}

class AuthScreenScaffold extends StatelessWidget {
  const AuthScreenScaffold({
    super.key,
    required this.child,
    this.showBack = true,
    this.onBack,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 28),
  });

  final Widget child;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: authScreenTheme(),
      child: Scaffold(
        backgroundColor: AuthScreenColors.background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: <Widget>[
                    if (showBack)
                      IconButton(
                        onPressed: () {
                          if (onBack != null) {
                            onBack!();
                            return;
                          }
                          authDismissKeyboardAndRun(
                            context,
                            () => Navigator.maybePop(context),
                          );
                        },
                        icon: const Icon(Icons.chevron_left_rounded),
                        color: Colors.white70,
                        style: IconButton.styleFrom(
                          backgroundColor: AuthScreenColors.card,
                          minimumSize: const Size(40, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 40, height: 40),
                    const Spacer(),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: _authScrollPadding(context, padding),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SafeCheckBrandLogo(),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Container(
              width: 18,
              height: 1.5,
              color: AuthScreenColors.accent,
            ),
            const SizedBox(width: 10),
            const Text(
              'SAFECHECK BY SAFEBANGLE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: AuthScreenColors.accent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AuthHeadline extends StatelessWidget {
  const AuthHeadline({
    super.key,
    required this.primary,
    this.accent,
  });

  final String primary;
  final String? accent;

  @override
  Widget build(BuildContext context) {
    if (accent == null) {
      return Text(
        primary,
        style: const TextStyle(
          fontSize: 34,
          height: 1.15,
          fontWeight: FontWeight.w700,
          fontFamily: 'Georgia',
          color: Colors.white,
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 34,
          height: 1.15,
          fontWeight: FontWeight.w700,
          fontFamily: 'Georgia',
        ),
        children: <TextSpan>[
          TextSpan(
            text: primary,
            style: const TextStyle(color: Colors.white),
          ),
          TextSpan(
            text: accent,
            style: const TextStyle(color: AuthScreenColors.accent),
          ),
        ],
      ),
    );
  }
}

class AuthBodyText extends StatelessWidget {
  const AuthBodyText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        height: 1.5,
        color: Colors.white.withValues(alpha: 0.62),
      ),
    );
  }
}

class AuthSecondaryButton extends StatelessWidget {
  const AuthSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class AuthLinkRow extends StatelessWidget {
  const AuthLinkRow({
    super.key,
    required this.prompt,
    required this.actionLabel,
    required this.onPressed,
  });

  final String prompt;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            prompt,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: AuthScreenColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
