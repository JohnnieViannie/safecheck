import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Official multicolor Google "G" mark for sign-in buttons.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        'assets/google_logo.svg',
        fit: BoxFit.contain,
      ),
    );
  }
}
