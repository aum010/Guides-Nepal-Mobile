import '../../l10n/app_strings.dart';
import '../../shared/models/app_user.dart';

/// Editable state of the signed-in traveler's profile.
///
/// Kept apart from the screen so the rules can be tested as rules. The server's
/// `ProfileUpdate` schema takes all of these as optional strings with no
/// validation of its own, so the app is where a blank name or a 4 000-character
/// bio has to be caught — and where the limits have to be honest about being
/// ours, not the server's.
class ProfileDraft {
  const ProfileDraft({
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.bio = '',
  });

  /// Practical caps for a phone form: long enough for an international
  /// number written with spaces, short enough to fit one line everywhere.
  static const int nameMaxLength = 60;
  static const int phoneMaxLength = 20;
  static const int bioMaxLength = 300;

  final String firstName;
  final String lastName;
  final String phone;
  final String bio;

  factory ProfileDraft.fromUser(AppUser user) => ProfileDraft(
        firstName: user.firstName ?? '',
        lastName: user.lastName ?? '',
        phone: user.phone ?? '',
        bio: user.bio ?? '',
      );

  ProfileDraft copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? bio,
  }) =>
      ProfileDraft(
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        phone: phone ?? this.phone,
        bio: bio ?? this.bio,
      );

  /// Field-keyed messages, empty when the draft may be sent.
  Map<String, String> validate() {
    final errors = <String, String>{};
    final first = firstName.trim();
    final last = lastName.trim();

    if (first.isEmpty && last.isEmpty) {
      errors['firstName'] = AppStrings.nameRequired;
    }
    if (first.length > nameMaxLength) {
      errors['firstName'] = AppStrings.fieldTooLong;
    }
    if (last.length > nameMaxLength) {
      errors['lastName'] = AppStrings.fieldTooLong;
    }

    final trimmedPhone = phone.trim();
    if (trimmedPhone.isNotEmpty) {
      final allowed = RegExp(r'^[0-9+\-() ]+$');
      if (!allowed.hasMatch(trimmedPhone) ||
          trimmedPhone.length > phoneMaxLength) {
        errors['phone'] = AppStrings.phoneInvalid;
      }
    }

    if (bio.trim().length > bioMaxLength) {
      errors['bio'] = AppStrings.fieldTooLong;
    }
    return errors;
  }

  bool get isValid => validate().isEmpty;

  /// Only the editable fields, trimmed. Empty phone/bio are sent as empty
  /// strings so clearing a field in the app clears it on the server.
  Map<String, dynamic> toJson() => {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'phone': phone.trim(),
        'bio': bio.trim(),
      };
}
