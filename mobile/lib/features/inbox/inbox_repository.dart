import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../shared/models/conversation.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';

/// Thin repository over the four conversation routes. All calls run
/// through the shared [ApiClient], so auth, renewal and error mapping
/// behave exactly as everywhere else in the app.
class InboxRepository {
  InboxRepository(this._api);

  final ApiClient _api;

  /// `GET /conversations` — threads the signed-in user belongs to.
  Future<List<Conversation>> fetchConversations() async {
    final response = await _api.get('/conversations');
    final data = response.data;
    return [
      if (data is List)
        for (final item in data)
          Conversation.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  /// `POST /conversations` — get-or-create the thread with a recipient
  /// (the guide assigned to a booking is the normal entry point).
  Future<Conversation> openWith(int recipientId) async {
    final response = await _api.post(
      '/conversations',
      data: {'recipient_id': recipientId},
    );
    return Conversation.fromJson(
      (response.data as Map).cast<String, dynamic>(),
    );
  }

  /// `GET /conversations/{id}/messages` — history in order. The server
  /// marks received messages read as a side effect of this fetch.
  Future<List<Message>> fetchMessages(int conversationId) async {
    final response = await _api.get('/conversations/$conversationId/messages');
    final data = response.data;
    return [
      if (data is List)
        for (final item in data)
          Message.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  /// `POST /conversations/{id}/messages` — send as the signed-in user.
  Future<Message> send(int conversationId, String body) async {
    final response = await _api.post(
      '/conversations/$conversationId/messages',
      data: {'body': body},
    );
    return Message.fromJson(
      (response.data as Map).cast<String, dynamic>(),
    );
  }
}

final inboxRepositoryProvider = Provider<InboxRepository>(
  (ref) => InboxRepository(ref.watch(apiClientProvider)),
);

/// All threads for the signed-in traveler. The Inbox tab refreshes this
/// on pull and on its poll tick; opening a thread from Trips invalidates
/// it so a newly opened conversation shows up immediately.
final conversationsProvider = FutureProvider.autoDispose<List<Conversation>>(
  (ref) {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isAuthenticated) {
    return Future.value(const <Conversation>[]);
  }
  return ref.watch(inboxRepositoryProvider).fetchConversations();
});

/// Unread messages across all threads — what the nav bar's Inbox badge
/// shows while the Inbox tab is not on screen. Watching this keeps
/// [conversationsProvider] alive, so the badge and the list share one fetch.
final unreadMessagesProvider = Provider.autoDispose<int>((ref) {
  final conversations = ref.watch(conversationsProvider);
  return conversations.maybeWhen(
    data: (list) => list.fold<int>(0, (sum, item) => sum + item.unreadCount),
    orElse: () => 0,
  );
});

/// One thread's message history, polled by the thread screen while it
/// is on screen.
final messagesProvider = FutureProvider.autoDispose
    .family<List<Message>, int>((ref, conversationId) {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isAuthenticated) {
    return Future.value(const <Message>[]);
  }
  return ref.watch(inboxRepositoryProvider).fetchMessages(conversationId);
});
