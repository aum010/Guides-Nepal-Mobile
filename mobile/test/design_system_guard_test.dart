import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that keep the design system the *only* source of visual truth.
///
/// Tokens are worthless if a screen can bypass them, and a one-off `Color(0xFF…)`
/// or `fontSize: 11` inside a feature is invisible in review until the palette
/// or type scale changes and that screen is left behind. These tests scan the
/// real source, so the rule fails the build rather than surviving on trust.
///
/// The allowlist is deliberately tiny: `lib/app/theme/` — the one place that is
/// *supposed* to hold raw values.
void main() {
  final libDir = Directory('lib');

  List<File> sources() => libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/app/theme/'))
      .toList();

  test('the token layer exists where the guard expects it', () {
    expect(libDir.existsSync(), isTrue,
        reason: 'run from the mobile/ package root');
    expect(
      File('lib/app/theme/app_colors.dart').existsSync() &&
          File('lib/app/theme/app_typography.dart').existsSync(),
      isTrue,
    );
    expect(sources(), isNotEmpty);
  });

  test('no raw colours outside lib/app/theme', () {
    final offenders = <String>[];
    final rawColor = RegExp(r'Color\(0x');
    for (final file in sources()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (rawColor.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use an AppColors token instead of a literal colour:\n'
            '${offenders.join('\n')}');
  });

  test('no Material palette colours outside lib/app/theme', () {
    // Colors.white / Colors.black bypass the warm palette entirely: a card that
    // is pure white reads as a hole punched in the cream canvas.
    final offenders = <String>[];
    final paletteColor = RegExp(r'Colors\.(white|black|grey|red|blue|green)\b');
    for (final file in sources()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (paletteColor.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use AppColors tokens (including the on-image ramp):\n'
            '${offenders.join('\n')}');
  });

  test('no hardcoded font sizes outside lib/app/theme', () {
    final offenders = <String>[];
    final fontSize = RegExp(r'fontSize\s*:');
    for (final file in sources()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (fontSize.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use an AppTypography style instead of a size:\n'
            '${offenders.join('\n')}');
  });

  test('no hardcoded font families outside lib/app/theme', () {
    final offenders = <String>[];
    final fontFamily = RegExp(r'''fontFamily\s*:\s*['"]''');
    for (final file in sources()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (fontFamily.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('inline copy never grows (AppStrings ratchet)', () {
    // `AppStrings` is meant to own user-facing copy so a translation pass has
    // one place to work. Some screens still build sentences inline with
    // interpolation, so instead of pretending the migration is finished this
    // pins the current count: it may fall, never rise. Delete entries from the
    // allowlist as each screen moves its copy into AppStrings.
    const baseline = 71;

    var count = 0;
    final offenders = <String>[];
    final inlineText = RegExp(r'''Text\(\s*['"]''');
    for (final file in sources()) {
      final path = file.path.replaceAll(r'\', '/');
      // The token layer contains no copy, but keep the filter explicit so a
      // future string in a theme file still fails this test.
      if (path.contains('lib/l10n/')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (inlineText.hasMatch(lines[i])) {
          count++;
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(count, lessThanOrEqualTo(baseline),
        reason: 'New copy belongs in lib/l10n/app_strings.dart. The $count '
            'inline string(s) found:\n${offenders.join('\n')}');
  });

  test('booking status is rendered by the one shared chip', () {
    // Trips (traveler) and the guide's request list show the same states; two
    // copies of the palette is how a cancelled booking turns green on one
    // screen. Any second status→colour mapping must fail here.
    final offenders = <String>[];
    final mapping = RegExp(r'BookingStatus\.(accepted|rejected|archived)\s*=>');
    for (final file in sources()) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith('shared/widgets/status_chip.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (mapping.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use BookingStatusChip instead of a local status map:\n'
            '${offenders.join('\n')}');
  });
}
