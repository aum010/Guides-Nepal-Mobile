/// Role of a chat participant in the Maila Dai conversation.
enum ChatRole { user, assistant }

/// One message in the Maila Dai conversation.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.isComplete = true,
  }) : createdAt = createdAt ?? DateTime.now();

  final ChatRole role;
  String content;
  final DateTime createdAt;

  /// False while a streaming reply is still being received.
  bool isComplete;

  Map<String, dynamic> toApiJson() => {
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'content': content,
      };
}
