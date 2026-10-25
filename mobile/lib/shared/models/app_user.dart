/// The authenticated account.
///
/// Parsed from the `user` object of `POST /auth/login|register` and from
/// `GET /profile/me` (which returns camelCase `avatarUrl`).
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.role = 'traveler',
    this.phone,
    this.bio,
    this.avatarUrl,
    this.isActive = true,
  });

  final int id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String role;
  final String? phone;
  final String? bio;
  final String? avatarUrl;
  final bool isActive;

  String get displayName {
    final name = [firstName, lastName]
        .where((p) => p != null && p.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (name.isNotEmpty) return name;
    return email;
  }

  String get initials {
    final f = firstName?.trim();
    final l = lastName?.trim();
    if ((f?.isNotEmpty ?? false) && (l?.isNotEmpty ?? false)) {
      return '${f![0]}${l![0]}'.toUpperCase();
    }
    if (f?.isNotEmpty ?? false) return f!.substring(0, 1).toUpperCase();
    if (email.isNotEmpty) return email.substring(0, 1).toUpperCase();
    return '?';
  }

  bool get isGuide => role == 'guide';
  bool get isTraveler => role == 'traveler';

  /// Token payload / `GET /profile/me` tolerant parser.
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        email: json['email'] as String? ?? '',
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        role: json['role'] as String? ?? 'traveler',
        phone: json['phone'] as String?,
        bio: json['bio'] as String?,
        avatarUrl: (json['avatarUrl'] ?? json['avatar_url']) as String?,
        isActive: (json['is_active'] ?? json['isActive']) as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'role': role,
        'phone': phone,
        'bio': bio,
        'avatarUrl': avatarUrl,
        'is_active': isActive,
      };

  AppUser copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) =>
      AppUser(
        id: id,
        email: email,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        role: role,
        phone: phone ?? this.phone,
        bio: bio ?? this.bio,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        isActive: isActive,
      );
}
