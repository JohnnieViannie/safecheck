import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.height = 48,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.centerLeft,
  });

  final double height;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      height: height,
      fit: fit,
      alignment: alignment,
      semanticLabel: 'SafeBangle',
    );
  }
}
