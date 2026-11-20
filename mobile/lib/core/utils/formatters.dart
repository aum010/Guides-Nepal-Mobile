import 'package:intl/intl.dart';

/// Display formatting for prices, dates and counts.
///
/// Currency policy: the backend prices are the platform's booking currency
/// (the web app displays them as USD by default). The app therefore shows
/// the booking currency as returned by the API and labels it explicitly —
/// no invented exchange rates are ever used. See `docs/api-gaps.md`.
abstract final class Formatters {
  static const String bookingCurrencyCode = 'USD';
  static const String bookingCurrencySymbol = r'$';

  static final NumberFormat _price = NumberFormat.currency(
    symbol: bookingCurrencySymbol,
    decimalDigits: 0,
  );
  static final NumberFormat _pricePrecise = NumberFormat.currency(
    symbol: bookingCurrencySymbol,
    decimalDigits: 2,
  );

  /// `$50` for whole amounts, `$49.50` otherwise.
  static String price(num value) {
    final isWhole = value == value.roundToDouble();
    return (isWhole ? _price : _pricePrecise).format(value);
  }

  /// Card price line, e.g. `$50 / person`.
  static String pricePerPerson(num value) => '${price(value)} / person';

  static String dateShort(DateTime d) => DateFormat('d MMM yyyy').format(d);

  static String dateWithWeekday(DateTime d) =>
      DateFormat('EEE, d MMM yyyy').format(d);

  static String time(DateTime d) => DateFormat('h:mm a').format(d);

  /// Short age for activity rows: `Just now`, `12 min ago`, `3 hr ago`,
  /// `Yesterday`, `4 days ago`, then an absolute date. A timestamp in the
  /// future (clock skew) reads as `Just now` rather than a negative age.
  ///
  /// Units are spelled the same way throughout (`min`, `hr`, `days`): a lone
  /// `h` after a space read as a typo in review, not as a deliberate
  /// abbreviation.
  static String relativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return dateShort(d);
  }

  /// Character counter for a capped field (`120/300`). Numeric formatting
  /// belongs here, not in a widget, so the widget stays free of layout copy.
  static String fieldCounter(int used, int max) => '$used/$max';

  static String reviewCount(int count) =>
      count == 1 ? '1 review' : '$count reviews';

  /// Compact count for tight layouts (card rating rows): `45`, `1.2k`.
  /// The spelled-out form stays available via [reviewCount] for
  /// accessibility labels and detail screens.
  static String reviewCountShort(int count) {
    if (count < 1000) return '$count';
    final thousands = count / 1000;
    return thousands >= 10
        ? '${thousands.round()}k'
        : '${thousands.toStringAsFixed(1)}k';
  }

  static String guests(int count) => count == 1 ? '1 guest' : '$count guests';
}
