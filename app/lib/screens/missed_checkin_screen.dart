import 'package:flutter/material.dart';
import 'package:safecheck/widgets/custom_button.dart';

class MissedCheckInScreen extends StatelessWidget {
  const MissedCheckInScreen({super.key, required this.onImSafe});

  final VoidCallback onImSafe;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 72),
              const SizedBox(height: 16),
              const Text(
                'You missed your check-in',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Tap below as soon as you are safe.'),
              const Spacer(),
              CustomButton(
                label: 'I\'m Safe',
                onPressed: () {
                  onImSafe();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
