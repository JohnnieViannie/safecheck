import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum SafeCheckNavIconType { home, checkIn, journey, history, contacts }

class SafeCheckNavIcon extends StatelessWidget {
  const SafeCheckNavIcon({
    super.key,
    required this.type,
    required this.color,
    this.size = 24,
  });

  final SafeCheckNavIconType type;
  final Color color;
  final double size;

  static const Map<SafeCheckNavIconType, String> _assetPaths =
      <SafeCheckNavIconType, String>{
    SafeCheckNavIconType.home: 'assets/icons/nav_home.svg',
    SafeCheckNavIconType.checkIn: 'assets/icons/nav_checkin.svg',
    SafeCheckNavIconType.history: 'assets/icons/nav_history.svg',
    SafeCheckNavIconType.contacts: 'assets/icons/nav_contacts.svg',
  };

  @override
  Widget build(BuildContext context) {
    if (type == SafeCheckNavIconType.journey) {
      return Icon(Icons.play_circle_outline, size: size, color: color);
    }
    return SvgPicture.asset(
      _assetPaths[type]!,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
