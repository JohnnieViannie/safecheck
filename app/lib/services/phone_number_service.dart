import 'package:phone_numbers_parser/phone_numbers_parser.dart';

class PhoneNumberService {
  PhoneNumberService._();

  static String? normalizeLocalToE164({
    required String rawInput,
    required String isoCode,
  }) {
    final String trimmed = rawInput.trim();
    if (trimmed.isEmpty || trimmed.startsWith('+')) {
      return null;
    }
    final String digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return null;

    try {
      final PhoneNumber number = PhoneNumber.parse(
        digitsOnly,
        callerCountry: IsoCode.values.byName(isoCode.toUpperCase()),
      );
      if (!number.isValid()) return null;
      return number.international;
    } catch (_) {
      return null;
    }
  }

  /// Digits-only local number for API POST (server normalizes to E164).
  static String? toLocalDigitsForApi({
    required String rawInput,
    required String isoCode,
  }) {
    if (normalizeLocalToE164(rawInput: rawInput, isoCode: isoCode) == null) {
      return null;
    }
    final String digitsOnly = rawInput.trim().replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly.isEmpty ? null : digitsOnly;
  }

  static String toLocalDisplay(String storedValue) {
    final String trimmed = storedValue.trim();
    if (trimmed.startsWith('+')) {
      try {
        final PhoneNumber number = PhoneNumber.parse(trimmed);
        return number.nsn;
      } catch (_) {
        return storedValue;
      }
    }
    return storedValue;
  }
}
