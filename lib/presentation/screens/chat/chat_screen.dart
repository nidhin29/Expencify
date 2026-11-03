import '../../widgets/app_menu_item.dart';
import 'package:intl/intl.dart';
import '../../widgets/ai_feature_gate.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../application/services/ai/ai_service.dart';
import '../../../application/services/ai/ai_guardrails.dart';
import '../../../application/services/chat/chat_prompt_context.dart';
import '../../../application/services/chat/chat_history_store.dart';

class ChatScreen extends StatefulWidget {
  final AIService? ai;
  final ChatHistoryStore? historyStore;
  const ChatScreen({super.key, this.ai, this.historyStore});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final _ai = widget.ai ?? AIService();
  late final _store = widget.historyStore ?? ChatHistoryStore();
  final List<ChatMessage> _messages = [];
  bool _loading = true, _thinking = false, _historyFailed = false;
  int? _generation;
  bool _hasEarlier = false, _loadingEarlier = false;
  List<Map<String, dynamic>> _memory = [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _restore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _restore() async {
    try {
      final snapshot = await _store.snapshot();
      if (!mounted) return;
      setState(() {
        _generation = snapshot.generation;
        _hasEarlier = snapshot.hasEarlier;
        _memory = snapshot.memory;
        _messages.clear();
        _messages.addAll(snapshot.messages);
        _historyFailed = false;
      });
      _scrollToEnd(force: true);
    } catch (_) {
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  Future<ChatMessage> _persist(ChatMessage message, {int? generation}) async {
    try {
      return await _store.save(message, generation: generation ?? _generation);
    } on ChatHistoryCleared {
      rethrow;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This message could not be saved to chat history.'),
          ),
        );
      }
      return message;
    }
  }

  Future<void> _send({String? prompt, int? retryAt}) async {
    final text = (prompt ?? _controller.text).trim();
    if (text.isEmpty ||
        text.length > AiGuardrails.maxChatChars ||
        _thinking ||
        _loading ||
        _loadingEarlier) {
      return;
    }
    final requestGeneration = _generation;
    setState(() => _thinking = true);
    try {
      if (retryAt == null) {
        _controller.clear();
        final message = ChatMessage(text: text, isUser: true);
        setState(() => _messages.add(message));
        final saved = await _persist(message, generation: requestGeneration);
        _messages[_messages.length - 1] = saved;
      }
      try {
        _memory = await _store.memory(generation: requestGeneration!);
      } on ChatHistoryCleared {
        rethrow;
      } catch (_) {
        /* Existing memory remains usable. */
      }
      _scrollToEnd(force: true);
      String reply;
      var failed = false;
      try {
        reply = await _ai.ask(
          text,
          history: _answeredHistory(text, beforeIndex: retryAt),
        );
        failed =
            reply.trim().isEmpty ||
            reply.startsWith('Error:') ||
            reply.startsWith('I could not complete') ||
            reply.startsWith('I could not reliably interpret') ||
            reply.startsWith('AI is processing') ||
            reply.startsWith('Chat is not ready') ||
            reply.startsWith('AI not initialized');
      } catch (_) {
        reply = '';
        failed = true;
      }
      if (failed &&
          !(reply.startsWith('I could not complete') ||
              reply.startsWith('I could not reliably interpret'))) {
        reply = 'Couldn’t get an answer. Try again.';
      }
      if (!mounted || _generation != requestGeneration) return;
      final old = retryAt != null && retryAt < _messages.length
          ? _messages[retryAt]
          : null;
      final answer = await _persist(
        ChatMessage(
          id: old?.id,
          text: reply,
          isUser: false,
          failed: failed,
          prompt: text,
        ),
        generation: requestGeneration,
      );
      if (!mounted || _generation != requestGeneration) return;
      final follow = !_scroll.hasClients || _scroll.position.extentAfter < 160;
      setState(() {
        _thinking = false;
        if (retryAt != null && retryAt < _messages.length) {
          _messages[retryAt] = answer;
        } else {
          _messages.add(answer);
        }
      });
      _scrollToEnd(force: follow);
    } on ChatHistoryCleared {
      await _restore();
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  void _scrollToEnd({bool force = false}) {
    if (!force) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Map<String, dynamic>> _answeredHistory(
    String current, {
    int? beforeIndex,
  }) {
    return ChatPromptContext.build(
      messages: _messages,
      memory: _memory,
      current: current,
      generation: _generation,
      beforeIndex: beforeIndex,
    );
  }

  Future<void> _newChat() async {
    if (_thinking || _loading || _loadingEarlier || _messages.isEmpty) return;
    try {
      await _store.newConversation(generation: _generation);
      if (!mounted) return;
      _controller.clear();
      await _restore();
    } catch (_) {
      _notice('Could not start a new chat. Try again.');
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _history() async {
    if (_thinking || _loading || _loadingEarlier) return;
    try {
      final sessions = await _store.conversations();
      if (!mounted) return;
      final selected = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Text(
                    'Chat history',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final item = sessions[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          selected: item.active,
                          selectedColor: AppIcons.actionColor(
                            Theme.of(context),
                          ),
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .07),
                          leading: const Icon(
                            Icons.chat_bubble_outline_rounded,
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormat.MMMd().add_jm().format(item.updated),
                          ),
                          trailing: item.active
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(
                            context,
                            item.active ? null : item.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      await _store.activate(selected, generation: _generation!);
      if (!mounted) return;
      _controller.clear();
      await _restore();
    } catch (_) {
      _notice('Could not load chat history. Try again.');
    }
  }

  Future<void> _earlier() async {
    if (_loadingEarlier ||
        _thinking ||
        _messages.isEmpty ||
        _messages.first.id == null) {
      return;
    }
    setState(() => _loadingEarlier = true);
    final epoch = _generation;
    final pixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    final extent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    try {
      final page = await _store.older(_messages.first.id!, generation: epoch!);
      if (!mounted || _generation != epoch) return;
      setState(() {
        _messages.insertAll(0, page.messages);
        _hasEarlier = page.hasEarlier;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && _generation == epoch) {
          _scroll.jumpTo(
            (pixels + _scroll.position.maxScrollExtent - extent).clamp(
              0.0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    } catch (_) {
      _notice('Could not load earlier messages. Try again.');
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  Future<void> _clear() async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text('Messages will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear != true) return;
    try {
      await _store.clear();
      await _restore();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not clear the conversation. Try again.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Spendy AI',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed:
                _thinking || _loading || _loadingEarlier || _messages.isEmpty
                ? null
                : _newChat,
          ),
          PopupMenuButton<String>(
            clipBehavior: Clip.antiAlias,
            tooltip: 'Conversation options',
            icon: const Icon(AppIcons.more),
            onSelected: (value) => value == 'history' ? _history() : _clear(),
            itemBuilder: (_) => [
              AppMenuItem(
                value: 'history',
                enabled: !_thinking && !_loadingEarlier,
                label: 'Chat history',
                icon: Icons.history_rounded,
              ),
              const PopupMenuDivider(height: 12),
              AppMenuItem(
                value: 'clear',
                enabled: !_thinking && !_loadingEarlier && _messages.isNotEmpty,
                label: 'Clear conversation',
                icon: AppIcons.delete,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(height: 16),
                  Text('Preparing chat…'),
                ],
              ),
            )
          : Column(
              children: [
                if (_historyFailed)
                  MaterialBanner(
                    content: const Text(
                      'Previous messages could not be loaded.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: _thinking ? null : _restore,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                Expanded(
                  child: _messages.isEmpty
                      ? _welcome(theme)
                      : ListView.builder(
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount:
                              _messages.length +
                              (_thinking ? 1 : 0) +
                              (_hasEarlier ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_hasEarlier && index == 0) {
                              return TextButton(
                                onPressed: _loadingEarlier ? null : _earlier,
                                child: Text(
                                  _loadingEarlier
                                      ? 'Loading earlier messages…'
                                      : 'Earlier messages',
                                ),
                              );
                            }
                            final i = index - (_hasEarlier ? 1 : 0);
                            return i == _messages.length
                                ? _working(theme)
                                : _bubble(_messages[i], i, theme);
                          },
                        ),
                ),
                if (_thinking && _messages.isEmpty) _working(theme),
                _input(theme),
              ],
            ),
    );
  }

  Widget _welcome(ThemeData theme) => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: bounds.maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  AppIcons.accounts,
                  color: theme.colorScheme.primary,
                  size: 27,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Ask about your spending',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'A clearer view of your money.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              _starter(
                'Spending overview',
                'Where did my money go this month?',
                AppIcons.reports,
              ),
              _starter(
                'Category breakdown',
                'Which category did I spend most on?',
                AppIcons.categories,
              ),
              _starter(
                'Recent spending',
                'Help me understand my recent spending.',
                AppIcons.transactions,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _starter(String title, String question, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: .12),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 3,
          ),
          leading: Icon(icon, size: 21, color: theme.colorScheme.primary),
          title: Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Icon(
            Icons.north_east_rounded,
            size: 17,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onTap: _thinking ? null : () => _send(prompt: question),
        ),
      ),
    );
  }

  Widget _working(ThemeData theme) => Semantics(
    liveRegion: true,
    label: 'Thinking',
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Thinking…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _bubble(ChatMessage message, int index, ThemeData theme) {
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 15.5,
      height: 1.55,
      color: theme.colorScheme.onSurface,
    );
    if (message.isUser) {
      return LayoutBuilder(
        builder: (context, bounds) => Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bounds.maxWidth * .86),
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 22),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(
                  alpha: theme.brightness == Brightness.dark ? .22 : .08,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: SelectableText(message.text, style: textStyle),
            ),
          ),
        ),
      );
    }
    final setup = message.text == AIService.conversationalSetupReply;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: message.failed
          ? const EdgeInsets.all(14)
          : const EdgeInsets.symmetric(horizontal: 4),
      decoration: message.failed
          ? BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: .18),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                message.failed ? AppIcons.error : AppIcons.accounts,
                size: 16,
                color: message.failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.failed ? 'Reply interrupted' : 'Spendy',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!message.failed && !setup)
                IconButton(
                  tooltip: 'Copy answer',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    AppIcons.copy,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => _copy(message.text),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(message.text, style: textStyle),
          if (setup)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: _thinking
                    ? null
                    : () async {
                        final ready = await ensureFeatureAiReady(
                          context,
                          service: _ai,
                        );
                        if (mounted && ready) {
                          _send(prompt: message.prompt, retryAt: index);
                        }
                      },
                child: const Text('Set up offline AI'),
              ),
            )
          else if (message.failed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: _thinking
                    ? null
                    : () => _send(prompt: message.prompt, retryAt: index),
                icon: const Icon(AppIcons.refresh, size: 16),
                label: const Text('Try again'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _notice('Answer copied');
    } catch (_) {
      _notice('Could not copy. Select the answer text to copy it.');
    }
  }

  Widget _input(ThemeData theme) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(
                alpha: theme.brightness == Brightness.dark ? .06 : .025,
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: .12),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: AiGuardrails.maxChatChars,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15.5,
                        height: 1.4,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask Spendy…',
                        counterText: '',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) => IconButton.filled(
                      tooltip: 'Send message',
                      onPressed:
                          !_thinking &&
                              !_loading &&
                              !_loadingEarlier &&
                              value.text.trim().isNotEmpty
                          ? () => _send()
                          : null,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        foregroundColor: theme.colorScheme.onPrimary,
                        backgroundColor: theme.colorScheme.primary,
                        disabledForegroundColor: theme
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: .5),
                        disabledBackgroundColor: theme.colorScheme.onSurface
                            .withValues(alpha: .08),
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 21),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'On-device AI',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
