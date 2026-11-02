import 'dart:math' as math;

import 'package:flutter/material.dart';

/// SafeBangle app icon / logo — light and dark variants.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.height = 48,
    this.maxWidth,
    this.alignment = Alignment.centerLeft,
    this.borderRadius,
  });

  final double height;
  final double? maxWidth;
  final Alignment alignment;
  final BorderRadius? borderRadius;

  static const String lightAssetPath = 'assets/logo.png';
  static const String darkAssetPath = 'assets/dark_mode_logo.png';

  static String assetForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? darkAssetPath : lightAssetPath;
  }

  @override
  Widget build(BuildContext context) {
    final double width = maxWidth == null ? height : math.min(height, maxWidth!);
    final String assetPath = assetForBrightness(Theme.of(context).brightness);

    final Widget image = Image.asset(
      assetPath,
      width: width,
      height: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      alignment: alignment,
    );

    return SizedBox(
      width: width,
      height: width,
      child: borderRadius == null
          ? image
          : ClipRRect(borderRadius: borderRadius!, child: image),
    );
  }
}

/// Teal tile + light logo — matches login / welcome screens.
class SafeCheckBrandLogo extends StatelessWidget {
  const SafeCheckBrandLogo({
    super.key,
    this.size = 56,
    this.logoSize = 36,
    this.cornerRadius = 14,
    this.innerCornerRadius = 8,
    this.accentColor = const Color(0xFF14B8A6),
  });

  final double size;
  final double logoSize;
  final double cornerRadius;
  final double innerCornerRadius;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accentColor,
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(innerCornerRadius),
          child: Image.asset(
            AppLogo.lightAssetPath,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
