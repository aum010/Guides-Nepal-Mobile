/// A traveller-facing guide update (`GET /updates?city=…`).
///
/// This is the only public surface for `guide_status_updates`: a guide posts
/// from their workspace and it reaches travellers scoped by **city**, because
/// the guide accounts that post updates are not linked to the legacy `guides`
/// catalog profiles travellers browse (see `docs/api-gaps.md`).
///
/// The server deliberately sends the guide's chosen display name and the
/// update text and nothing else identifying — no user id, no email, no
/// traveller details — so this parser keeps no more than it is given.
class CityUpdate {
  const CityUpdate({
    required this.id,
    required this.updateType,
    required this.message,
    required this.guideName,
    this.area,
    this.eventDate,
    this.currentCapacity,
    this.maxCapacity,
    this.createdAt,
    this.listingTitle,
    this.cities = const [],
  });

  /// The backend's `GuideUpdateType` values, minus `booking` — that type is
  /// written for a guide's own workflow about one reservation and is never
  /// returned to travellers.
  static const List<String> publicTypes = [
    'announcement',
    'availability',
    'capacity',
    'schedule',
  ];

  final int id;
  final String updateType;
  final String message;
  final String guideName;
  final String? area;
  final DateTime? eventDate;
  final int? currentCapacity;
  final int? maxCapacity;
  final DateTime? createdAt;

  /// The listing this update is about, when it is attached to one.
  final String? listingTitle;

  /// Every city this update applies to: the listing's city, or all the cities
  /// the guide declared on their profile for a guide-wide note.
  final List<String> cities;

  factory CityUpdate.fromJson(Map<String, dynamic> json) => CityUpdate(
        id: (json['id'] as num?)?.toInt() ?? 0,
        updateType: json['update_type'] as String? ?? 'announcement',
        message: json['message'] as String? ?? '',
        guideName: json['guide_name'] as String? ?? 'A local guide',
        area: json['area'] as String?,
        eventDate: DateTime.tryParse(json['event_date'] as String? ?? ''),
        currentCapacity: (json['current_capacity'] as num?)?.toInt(),
        maxCapacity: (json['max_capacity'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        listingTitle: json['listing_title'] as String?,
        cities: _strList(json['cities']),
      );

  static List<String> _strList(Object? v) =>
      v is List ? v.whereType<String>().toList(growable: false) : const [];

  /// `capacity` → `Capacity`. An unknown value is shown as written rather
  /// than hidden.
  String get typeLabel => updateType.isEmpty
      ? 'Update'
      : '${updateType[0].toUpperCase()}${updateType.substring(1)}';

  /// `6/8 spots` for a capacity note, otherwise `null`. A half-filled pair
  /// (the server allows either alone) is shown as just what is known.
  String? get capacityLabel {
    final current = currentCapacity;
    final max = maxCapacity;
    if (current == null && max == null) return null;
    if (current != null && max != null) return '$current/$max spots';
    if (max != null) return 'Up to $max spots';
    return '$current spots taken';
  }
}
