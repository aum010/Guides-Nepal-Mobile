import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/chat_message.dart';
import 'ai_repository.dart';

/// Suggested prompts shown before the first message.
const _suggestedQuestions = [
  'What should I explore in Kathmandu?',
  'Where can I experience authentic Newari food?',
  'Which cultural experiences are available in Bhaktapur?',
  'Help me plan a three-day trip around Pokhara.',
];

/// Maila Dai: the Guides Nepal AI travel assistant.
///
/// Streams replies from the verified `/ai/chat/stream` endpoint with a
/// fallback to `/ai/chat`. Assistant replies are never fabricated — the only
/// text shown comes from the backend stream, and a failed send keeps the
/// user's message so it can be retried.
class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  StreamSubscription<String>? _subscription;
  bool _busy = false;
  String? _error;
  ChatMessage? _streaming;

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;

    _controller.clear();
    setState(() {
      _error = null;
      _messages.add(ChatMessage(role: ChatRole.user, content: trimmed));
      _streaming = ChatMessage(role: ChatRole.assistant, content: '');
      _busy = true;
    });
    _scrollToBottom();

    final reply = _streaming!;
    final repo = ref.read(aiRepositoryProvider);
    final buffer = StringBuffer();

    _subscription = repo.streamChat(List.of(_messages)).listen(
      (fragment) {
        buffer.write(fragment);
        if (!mounted) return;
        setState(() => reply.content = buffer.toString());
        _scrollToBottom();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _streaming = null;
          _messages.removeLast(); // let the user retry the same message
          _error = e is ApiException
              ? e.message
              : 'Maila Dai is unreachable right now. Please try again.';
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _streaming = null;
          reply.isComplete = true;
          _messages.add(reply);
        });
        _scrollToBottom();
      },
      cancelOnError: true,
    );
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
    setState(() {
      _busy = false;
      _streaming = null;
      _messages.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSuggestions = _messages.isEmpty && _streaming == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.mailaDai, style: AppTypography.h3),
            Text('Local travel assistant',
                style: AppTypography.caption),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Start a new conversation',
            icon: const Icon(Icons.refresh),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _messages.clear();
                      _error = null;
                      _streaming = null;
                    }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: showSuggestions
                  ? _intro()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      itemCount: _messages.length + (_streaming != null ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i < _messages.length) {
                          return _Bubble(message: _messages[i]);
                        }
                        return _Bubble(message: _streaming!, isStreaming: _busy);
                      },
                    ),
            ),
            if (_error != null) _ErrorBanner(message: _error!),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _intro() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.x5),
          decoration: BoxDecoration(
            color: AppColors.surfacePeach,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.surface,
                child: Icon(Icons.smart_toy_outlined,
                    color: AppColors.secondary),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Text(AppStrings.mailaDaiIntro,
                    style: AppTypography.body),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x6),
        Text('Try asking', style: AppTypography.h3),
        const SizedBox(height: AppSpacing.x3),
        for (final q in _suggestedQuestions) ...[
          _SuggestionChip(label: q, onTap: () => _send(q)),
          const SizedBox(height: AppSpacing.x2),
        ],
      ],
    );
  }

  Widget _composer() {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.x2,
        top: AppSpacing.x2,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.x2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: const InputDecoration(
                hintText: 'Ask Maila Dai anything…',
                border: InputBorder.none,
              ),
            ),
          ),
          _busy
              ? IconButton(
                  tooltip: 'Stop generating',
                  icon: const Icon(Icons.stop_circle_outlined,
                      color: AppColors.error, size: 28),
                  onPressed: _cancel,
                )
              : IconButton(
                  tooltip: 'Send',
                  icon: const Icon(Icons.send_rounded,
                      color: AppColors.secondary, size: 24),
                  onPressed: () => _send(_controller.text),
                ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.isStreaming = false});

  final ChatMessage message;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x3),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.surfacePeach,
              child: Icon(Icons.smart_toy_outlined,
                  size: 16, color: AppColors.secondary),
            ),
            const SizedBox(width: AppSpacing.x2),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x4, vertical: AppSpacing.x3),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppSpacing.radiusLg),
                  topRight: const Radius.circular(AppSpacing.radiusLg),
                  bottomLeft: Radius.circular(
                      isUser ? AppSpacing.radiusLg : AppSpacing.x1),
                  bottomRight: Radius.circular(
                      isUser ? AppSpacing.x1 : AppSpacing.radiusLg),
                ),
                border: isUser
                    ? null
                    : Border.all(color: AppColors.border),
              ),
              child: message.content.isEmpty && isStreaming
                  ? const _TypingDots()
                  : Text(
                      message.content,
                      style: AppTypography.body.copyWith(
                        color: isUser
                            ? AppColors.textOnPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      return const SizedBox(
        width: 24,
        height: 12,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('…'),
        ),
      );
    }
    return SizedBox(
      width: 36,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final phase = ((_controller.value - i * 0.2) % 1.0 + 1.0) % 1.0;
              // Triangle wave: rises 0 -> 1 over the first half, falls back
              // over the second, so each dot pulses in sequence.
              final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
              return Opacity(
                opacity: 0.3 + 0.7 * wave,
                child: const CircleAvatar(
                    radius: 3, backgroundColor: AppColors.secondary),
              );
            }),
          );
        },
      ),
    );
  }

}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.x2),
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Text(message,
                style: AppTypography.small.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4, vertical: AppSpacing.x3),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: Text(label, style: AppTypography.bodyMedium),
        ),
      ),
    );
  }
}
