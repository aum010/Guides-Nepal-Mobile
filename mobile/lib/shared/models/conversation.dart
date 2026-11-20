/// Direct-message thread models, mirroring `GET/POST /api/v1/conversations`
/// and its `/messages` sub-resource (backend/app/api/v1/conversations.py).
///
/// Parsers are tolerant in the house style: missing fields degrade to safe
/// defaults so an older server payload never crashes the Inbox.
library;

/// The counterpart account, as the viewer sees it. The API returns a
/// viewer-relative `peer` object with camelCase name fields (matching
/// `GET /profile/me` and [AppUser]).
class ConversationPeer {
  const ConversationPeer({
    required this.id,
    this.firstName,
    this.lastName,
    this.avatarUrl,
    this.role = 'traveler',
  });

  final int id;
  final String? firstName;
  final String? lastName;
  final String? avatarUrl;
  final String role;

  bool get isGuide => role == 'guide';

  /// Full name, falling back to a role label when the account has no
  /// names on file (the conversations payload carries no email).
  String get displayName {
    final name = [firstName, lastName]
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (name.isNotEmpty) return name;
    return isGuide ? 'Guide' : 'Traveler';
  }

  /// Avatar initials — first letters of the names, else one letter from
  /// the role label.
  String get initials {
    final first = firstName?.trim();
    final last = lastName?.trim();
    if (first != null && first.isNotEmpty && last != null && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    if (first != null && first.isNotEmpty) {
      return first.substring(0, 1).toUpperCase();
    }
    return displayName.substring(0, 1).toUpperCase();
  }

  factory ConversationPeer.fromJson(Map<String, dynamic> json) =>
      ConversationPeer(
        id: (json['id'] as num?)?.toInt() ?? 0,
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        role: json['role'] as String? ?? 'traveler',
      );
}

/// Preview of the newest message in a thread.
class LastMessage {
  const LastMessage({
    required this.id,
    required this.body,
    required this.senderId,
    required this.createdAt,
  });

  final int id;
  final String body;
  final int senderId;
  final DateTime createdAt;

  factory LastMessage.fromJson(Map<String, dynamic> json) => LastMessage(
        id: (json['id'] as num?)?.toInt() ?? 0,
        body: json['body'] as String? ?? '',
        senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

/// One row of the Inbox list.
class Conversation {
  const Conversation({
    required this.id,
    required this.peer,
    required this.createdAt,
    this.lastMessage,
    this.unreadCount = 0,
  });

  final int id;
  final ConversationPeer peer;
  final LastMessage? lastMessage;
  final int unreadCount;
  final DateTime createdAt;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: (json['id'] as num?)?.toInt() ?? 0,
        peer: ConversationPeer.fromJson(
          (json['peer'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        lastMessage: json['last_message'] == null
            ? null
            : LastMessage.fromJson(
                (json['last_message'] as Map).cast<String, dynamic>(),
              ),
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

/// One message inside a thread. Fetching the thread marks received
/// messages read server-side, which is what clears unread counts.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final int id;
  final int conversationId;
  final int senderId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: (json['id'] as num?)?.toInt() ?? 0,
        conversationId: (json['conversation_id'] as num?)?.toInt() ?? 0,
        senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
        body: json['body'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.tryParse(json['read_at'] as String)?.toLocal(),
      );
}
