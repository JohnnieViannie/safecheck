import 'package:flutter/material.dart';
import 'package:safecheck/theme.dart';

class AuthStepIndicator extends StatelessWidget {
  const AuthStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.labels = const <String>['Account', 'Verify', 'Profile'],
  });

  final int currentStep;
  final int totalSteps;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color inactive = isDark ? Colors.white24 : Colors.grey.shade300;
    final Color active = AppTheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Step $currentStep of $totalSteps',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: List<Widget>.generate(totalSteps, (int index) {
            final int stepNumber = index + 1;
            final bool isActive = stepNumber <= currentStep;
            final String label = index < labels.length ? labels[index] : '';
            return Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: isActive ? active : inactive,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        if (label.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: stepNumber == currentStep
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: stepNumber == currentStep
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.white38 : Colors.black38),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (index < totalSteps - 1) const SizedBox(width: 8),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}
