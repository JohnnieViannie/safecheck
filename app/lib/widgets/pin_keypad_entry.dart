import 'package:flutter/material.dart';

class PinKeypadEntry extends StatefulWidget {
  const PinKeypadEntry({
    super.key,
    required this.tipText,
    required this.onCompleted,
    this.enabled = true,
    this.errorText,
    this.onChanged,
  });

  final String tipText;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final String? errorText;
  final VoidCallback? onChanged;

  static const Color cardBackground = Color(0xFF112240);
  static const Color accent = Color(0xFF14B8A6);

  static const List<String> _keypadLetters = <String>[
    '',
    '',
    'ABC',
    'DEF',
    'GHI',
    'JKL',
    'MNO',
    'PQRS',
    'TUV',
    'WXYZ',
  ];

  @override
  State<PinKeypadEntry> createState() => PinKeypadEntryState();
}

class PinKeypadEntryState extends State<PinKeypadEntry> {
  String _pin = '';

  void reset() {
    setState(() => _pin = '');
  }

  String get pin => _pin;

  void _setPin(String value) {
    if (!widget.enabled) return;
    setState(() => _pin = value);
    widget.onChanged?.call();
    if (_pin.length == 4) {
      widget.onCompleted(_pin);
    }
  }

  void _appendDigit(String digit) {
    if (_pin.length >= 4) return;
    _setPin('$_pin$digit');
  }

  void _clearPin() {
    _setPin('');
  }

  void _backspacePin() {
    if (_pin.isEmpty) return;
    _setPin(_pin.substring(0, _pin.length - 1));
  }

  Widget _buildPinBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(4, (int index) {
        final bool filled = index < _pin.length;
        return Padding(
          padding: EdgeInsets.only(left: index == 0 ? 0 : 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PinKeypadEntry.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.errorText != null
                    ? Colors.redAccent.withValues(alpha: 0.7)
                    : filled
                        ? PinKeypadEntry.accent.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.12),
                width: filled ? 1.5 : 1,
              ),
            ),
            child: Text(
              filled ? _pin[index] : '',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildKeypadButton({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 64,
            decoration: BoxDecoration(
              color: PinKeypadEntry.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _digitButton(int digit) {
    return _buildKeypadButton(
      onTap: () => _appendDigit('$digit'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '$digit',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          if (digit < PinKeypadEntry._keypadLetters.length &&
              PinKeypadEntry._keypadLetters[digit].isNotEmpty)
            Text(
              PinKeypadEntry._keypadLetters[digit],
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: Colors.white.withValues(alpha: 0.38),
                height: 1.2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _keypadRow(List<Widget> buttons) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < buttons.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 10),
            buttons[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 28),
        _buildPinBoxes(),
        if (widget.errorText != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            widget.errorText!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 32),
        Column(
          children: <Widget>[
            _keypadRow(<Widget>[_digitButton(1), _digitButton(2), _digitButton(3)]),
            _keypadRow(<Widget>[_digitButton(4), _digitButton(5), _digitButton(6)]),
            _keypadRow(<Widget>[_digitButton(7), _digitButton(8), _digitButton(9)]),
            _keypadRow(<Widget>[
              _buildKeypadButton(
                onTap: _clearPin,
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ),
              _digitButton(0),
              _buildKeypadButton(
                onTap: _backspacePin,
                child: Icon(
                  Icons.backspace_outlined,
                  size: 22,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PinKeypadEntry.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.tipText,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
