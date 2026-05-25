import 'package:flutter/material.dart';
import 'package:safecheck/theme.dart';

/// A social sign-in button (Google / Apple style) with icon, label, and
/// optional loading spinner.
class SocialSignInButton extends StatelessWidget {
  const SocialSignInButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor:
              backgroundColor ?? (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          foregroundColor:
              foregroundColor ?? (isDark ? Colors.white : Colors.black87),
          side: BorderSide(
            color: borderColor ??
                (isDark ? Colors.white24 : Colors.grey.shade300),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: loading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor ??
                      (isDark ? Colors.white : Colors.black54),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: foregroundColor ??
                          (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
