import 'package:flutter/material.dart';
import 'package:safecheck/theme.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.backgroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppTheme.elevatedButtonTheme.style?.minimumSize?.resolve({})?.height ?? 56,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: backgroundColor != null
            ? ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.borderRadius)),
                minimumSize: const Size.fromHeight(56),
              )
            : Theme.of(context).elevatedButtonTheme.style,
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)),
      ),
    );
  }
}
