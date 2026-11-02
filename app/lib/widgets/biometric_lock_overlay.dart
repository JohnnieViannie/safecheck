import 'package:flutter/material.dart';

class BiometricLockOverlay extends StatelessWidget {
  const BiometricLockOverlay({
    super.key,
    required this.onUnlock,
    this.onTurnOffLock,
    this.errorMessage,
    this.busy = false,
  });

  final Future<void> Function() onUnlock;
  final Future<void> Function()? onTurnOffLock;
  final String? errorMessage;
  final bool busy;

  static const Color _background = Color(0xFF0A192F);
  static const Color _accent = Color(0xFF14B8A6);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.fingerprint_rounded,
                  size: 72,
                  color: _accent,
                ),
                const SizedBox(height: 24),
                const Text(
                  'SafeCheck is locked',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Use Face ID or fingerprint to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                if (errorMessage != null && errorMessage!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFFCA5A5),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: busy ? null : () => onUnlock(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _background,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint_rounded),
                  label: Text(busy ? 'Checking…' : 'Unlock with biometrics'),
                ),
                if (onTurnOffLock != null) ...<Widget>[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: busy ? null : () => onTurnOffLock!(),
                    child: Text(
                      'Turn off biometric lock',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
