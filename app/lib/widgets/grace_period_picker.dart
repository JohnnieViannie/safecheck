import 'package:flutter/material.dart';

class GracePreset {
  const GracePreset({
    required this.label,
    required this.emoji,
    this.minutes,
    this.isCustom = false,
  });

  final String label;
  final String emoji;
  final int? minutes;
  final bool isCustom;

  String get durationLabel {
    if (isCustom) {
      return 'Set your own';
    }
    final int value = minutes ?? 0;
    if (value < 60) {
      return '$value min';
    }
    if (value % 60 == 0) {
      final int hours = value ~/ 60;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return '${value ~/ 60}h ${value % 60}m';
  }
}

class GracePeriodPicker extends StatefulWidget {
  const GracePeriodPicker({
    super.key,
    required this.initialMinutes,
    required this.onChanged,
  });

  final int initialMinutes;
  final ValueChanged<int> onChanged;

  static const Color accent = Color(0xFF14B8A6);
  static const Color cardBackground = Color(0xFF112240);
  static const Color background = Color(0xFF0A192F);

  static const List<int> graceStepMinutes = <int>[
    15,
    30,
    45,
    60,
    90,
    120,
    180,
    240,
    360,
    720,
    1440,
  ];

  static const List<int> customMinuteOptions = <int>[0, 15, 30, 45];

  static const List<GracePreset> gracePresets = <GracePreset>[
    GracePreset(label: 'Living Alone', emoji: '🏠', minutes: 120),
    GracePreset(label: 'Field Worker', emoji: '🏕️', minutes: 180),
    GracePreset(label: 'Lone Worker', emoji: '🏗️', minutes: 240),
    GracePreset(label: 'Traveller', emoji: '✈️', minutes: 360),
    GracePreset(label: 'Custom', emoji: '⚙️', isCustom: true),
  ];

  static int snapGraceMinutes(int minutes) {
    int closest = graceStepMinutes.first;
    int minDiff = (minutes - closest).abs();
    for (final int step in graceStepMinutes) {
      final int diff = (minutes - step).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = step;
      }
    }
    return closest;
  }

  static String formatGraceDuration(int minutes) {
    if (minutes < 60) {
      return minutes == 1 ? '1 minute' : '$minutes minutes';
    }
    final int hours = minutes ~/ 60;
    final int mins = minutes % 60;
    if (mins == 0) {
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    final String hourPart = hours == 1 ? '1 hour' : '$hours hours';
    final String minutePart = mins == 1 ? '1 minute' : '$mins minutes';
    return '$hourPart $minutePart';
  }

  static String formatGraceLabel(int minutes) {
    if (minutes < 60) {
      return minutes == 1 ? '1 min' : '$minutes min';
    }
    if (minutes % 60 == 0) {
      final int hours = minutes ~/ 60;
      return hours == 1 ? '1 hr' : '$hours hrs';
    }
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  @override
  State<GracePeriodPicker> createState() => _GracePeriodPickerState();
}

class _GracePeriodPickerState extends State<GracePeriodPicker> {
  late int _graceMinutes;
  bool _graceCustomMode = false;
  int _customGraceHours = 2;
  int _customGraceMinutes = 0;

  @override
  void initState() {
    super.initState();
    _graceMinutes = widget.initialMinutes.clamp(15, 1440);
    _syncCustomPartsFromMinutes();
    if (!GracePeriodPicker.graceStepMinutes.contains(_graceMinutes)) {
      _graceCustomMode = true;
    }
  }

  int get _graceSliderIndex {
    if (_graceCustomMode) {
      return -1;
    }
    final int index = GracePeriodPicker.graceStepMinutes.indexOf(_graceMinutes);
    return index >= 0
        ? index
        : GracePeriodPicker.graceStepMinutes.indexOf(120);
  }

  String _graceSummaryText() {
    return 'We\'ll wait ${GracePeriodPicker.formatGraceDuration(_graceMinutes)} before notifying your contacts';
  }

  void _syncCustomPartsFromMinutes() {
    _customGraceHours = _graceMinutes ~/ 60;
    _customGraceMinutes = _graceMinutes % 60;
  }

  void _notifyChanged() {
    widget.onChanged(_graceMinutes);
  }

  void _setGraceMinutes(int minutes, {bool custom = false}) {
    setState(() {
      _graceMinutes = minutes.clamp(15, 1440);
      _graceCustomMode = custom;
      if (custom) {
        _syncCustomPartsFromMinutes();
      }
    });
    _notifyChanged();
  }

  void _setGraceFromSlider(int index) {
    setState(() {
      _graceMinutes = GracePeriodPicker.graceStepMinutes[index];
      _graceCustomMode = false;
    });
    _notifyChanged();
  }

  void _setCustomGraceParts({int? hours, int? minutes}) {
    final int nextHours = hours ?? _customGraceHours;
    final int nextMinutes = minutes ?? _customGraceMinutes;
    final int total = (nextHours * 60) + nextMinutes;
    setState(() {
      _customGraceHours = nextHours.clamp(0, 24);
      _customGraceMinutes =
          GracePeriodPicker.customMinuteOptions.contains(nextMinutes)
              ? nextMinutes
              : 0;
      _graceMinutes = total.clamp(15, 1440);
      _graceCustomMode = true;
    });
    _notifyChanged();
  }

  void _applyGracePreset(GracePreset preset) {
    if (preset.isCustom) {
      _setGraceMinutes(_graceMinutes, custom: true);
      return;
    }
    _setGraceMinutes(preset.minutes ?? 120);
  }

  bool _isGracePresetSelected(GracePreset preset) {
    if (preset.isCustom) {
      return _graceCustomMode;
    }
    return !_graceCustomMode && _graceMinutes == preset.minutes;
  }

  ({String value, String unit}) _graceDisplayParts() {
    if (_graceMinutes < 60) {
      return (value: '$_graceMinutes', unit: 'min');
    }
    if (_graceMinutes % 60 == 0) {
      final int hours = _graceMinutes ~/ 60;
      return (
        value: '$hours',
        unit: hours == 1 ? 'hour' : 'hours',
      );
    }
    return (
      value: '${_graceMinutes ~/ 60}h ${_graceMinutes % 60}m',
      unit: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ({String value, String unit}) display = _graceDisplayParts();
    final int sliderIndex = _graceSliderIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: GracePeriodPicker.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: GracePeriodPicker.accent.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    display.value,
                    style: const TextStyle(
                      fontSize: 56,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: GracePeriodPicker.accent,
                    ),
                  ),
                  if (display.unit.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        display.unit,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _graceSummaryText(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (!_graceCustomMode) ...<Widget>[
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: GracePeriodPicker.accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: Colors.white,
              overlayColor: GracePeriodPicker.accent.withValues(alpha: 0.15),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: sliderIndex.toDouble(),
              min: 0,
              max: (GracePeriodPicker.graceStepMinutes.length - 1).toDouble(),
              divisions: GracePeriodPicker.graceStepMinutes.length - 1,
              onChanged: (double value) => _setGraceFromSlider(value.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  '15 min',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                Text(
                  '6 hrs',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                Text(
                  '12 hrs',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                Text(
                  '24 hrs',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ] else
          _buildCustomGracePicker(),
        const SizedBox(height: 24),
        Text(
          'SMART PRESETS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemCount: GracePeriodPicker.gracePresets.length,
          itemBuilder: (BuildContext context, int index) {
            final GracePreset preset = GracePeriodPicker.gracePresets[index];
            final bool selected = _isGracePresetSelected(preset);
            return GestureDetector(
              onTap: () => _applyGracePreset(preset),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: GracePeriodPicker.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? GracePeriodPicker.accent
                        : Colors.white.withValues(alpha: 0.06),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(preset.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 8),
                    Text(
                      preset.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      preset.durationLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: GracePeriodPicker.accent,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCustomGracePicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GracePeriodPicker.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GracePeriodPicker.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Custom grace period',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Hours',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: GracePeriodPicker.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _customGraceHours,
                          isExpanded: true,
                          dropdownColor: GracePeriodPicker.cardBackground,
                          items: List<DropdownMenuItem<int>>.generate(
                            25,
                            (int index) => DropdownMenuItem<int>(
                              value: index,
                              child: Text('$index'),
                            ),
                          ),
                          onChanged: (int? value) {
                            if (value == null) return;
                            _setCustomGraceParts(hours: value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Minutes',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: GracePeriodPicker.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _customGraceMinutes,
                          isExpanded: true,
                          dropdownColor: GracePeriodPicker.cardBackground,
                          items: GracePeriodPicker.customMinuteOptions
                              .map(
                                (int value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: (int? value) {
                            if (value == null) return;
                            _setCustomGraceParts(minutes: value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Minimum 15 minutes. Maximum 24 hours.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
