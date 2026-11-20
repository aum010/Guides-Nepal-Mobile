/// Booking status values from `backend/app/schemas/booking.py`.
enum BookingStatus {
  upcoming('upcoming'),
  accepted('accepted'),
  rejected('rejected'),
  completed('completed'),
  cancelled('cancelled'),
  archived('archived');

  const BookingStatus(this.rawValue);
  final String rawValue;

  static BookingStatus fromString(String? value) => BookingStatus.values
      .firstWhere((s) => s.rawValue == value, orElse: () => BookingStatus.upcoming);

  bool get isActive => this == BookingStatus.upcoming || this == BookingStatus.accepted;
  bool get canCancel =>
      this == BookingStatus.upcoming || this == BookingStatus.accepted;
}

/// Booking as returned by `GET/POST /api/v1/bookings`.
class Booking {
  const Booking({
    required this.id,
    required this.experienceId,
    required this.experienceTitle,
    required this.city,
    required this.date,
    required this.guests,
    required this.price,
    required this.status,
    required this.userId,
    required this.createdAt,
    this.image,
    this.guideUserId,
    this.guideName,
  });

  final int id;
  final int experienceId;
  final String experienceTitle;
  final String city;
  final DateTime date;
  final int guests;
  final double price;
  final BookingStatus status;
  final int userId;
  final DateTime createdAt;
  final String? image;

  /// The guide account assigned to this booking — the recipient of the
  /// "Message guide" thread. Null until a guide is linked.
  final int? guideUserId;
  final String? guideName;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: (json['id'] as num?)?.toInt() ?? 0,
        experienceId: (json['experience_id'] as num?)?.toInt() ?? 0,
        experienceTitle: json['experience_title'] as String? ?? '',
        city: json['city'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        guests: (json['guests'] as num?)?.toInt() ?? 1,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        status: BookingStatus.fromString(json['status'] as String?),
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        image: json['image'] as String?,
        guideUserId: (json['guide_user_id'] as num?)?.toInt(),
        guideName: json['guide_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'experience_id': experienceId,
        'experience_title': experienceTitle,
        'city': city,
        'date': date.toUtc().toIso8601String(),
        'guests': guests,
        'price': price,
        'status': status.rawValue,
        'user_id': userId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'image': image,
        'guide_user_id': guideUserId,
        'guide_name': guideName,
      };
}
