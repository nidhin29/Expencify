import 'package:flutter/material.dart';
import 'package:expencify/application/services/ai/ai_service.dart';
import 'package:expencify/application/services/ai/local_ai_model.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AIService _ai = AIService();

  bool _isInit = false;
  bool _isThinking = false;
  double _downloadProgress = 0;
  bool _isDownloading = false;
  bool _isChecking = true;
  LocalAIModelMetadata? _selectedModel;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isChecking = true);

    // Find if any model is already installed
    LocalAIModelMetadata? installed;
    for (var m in LocalAIModelMetadata.all) {
      if (await _ai.modelExists(m.id)) {
        installed = m;
        break;
      }
    }

    if (installed != null) {
      await _ai.init(installed.id);
      if (mounted) {
        setState(() {
          _isInit = true;
          _isChecking = false;
          if (_messages.isEmpty) {
            _messages.add({
              'text':
                  'Hello! I am Expencify AI, your AI financial assistant. How can I help you today?',
              'isUser': false,
            });
          }
        });
      }
    } else {
      // Automatic download of default model (Qwen Lite)
      final defaultModel = LocalAIModelMetadata.all.firstWhere(
        (m) => m.id == LocalAIModelType.qwenLite,
      );
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
        await _download(defaultModel);
      }
    }
  }

  Future<void> _download(LocalAIModelMetadata metadata) async {
    if (!mounted) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _selectedModel = metadata;
    });
    try {
      await _ai.downloadModel(
        metadata,
        (p) => setState(() => _downloadProgress = p),
      );
      await _checkStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add({'text': text, 'isUser': true});
      _isThinking = true;
    });
    _scrollToBottom();

    final response = await _ai.ask(text, history: _messages);

    if (mounted) {
      setState(() {
        _isThinking = false;
        _messages.add({'text': response, 'isUser': false});
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expencify AI',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 10,
                  color: Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  '100% On-Device & Private',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: _buildContent(theme, isDark),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    if (_isChecking) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Initializing intelligence...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    if (_isDownloading) {
      return _buildDownloadProgress(theme);
    }

    if (!_isInit) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Failed to initialize AI.'),
            TextButton(onPressed: _checkStatus, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.errorContainer.withOpacity(0.3),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This chatbot provides general budgeting guidance and does not constitute financial, investment, or tax advice.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_isThinking ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == _messages.length) {
                return _buildThinkingBubble(theme, isDark);
              }
              final msg = _messages[i];
              return _buildChatBubble(
                msg['text'],
                msg['isUser'],
                theme,
                isDark,
              );
            },
          ),
        ),
        _buildInput(theme, isDark),
      ],
    );
  }

  Widget _buildDownloadProgress(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: _downloadProgress,
                      strokeWidth: 8,
                      backgroundColor: theme.colorScheme.primary.withOpacity(
                        0.1,
                      ),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Icon(
                    Icons.cloud_download_rounded,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'Preparing your Intelligence',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Downloading ${_selectedModel?.name ?? "AI Model"}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: theme.dividerColor),
                  const SizedBox(width: 12),
                  Text(
                    'Size: ${_selectedModel?.size ?? "Unknown"}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(
    String text,
    bool isUser,
    ThemeData theme,
    bool isDark,
  ) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : (isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingBubble(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.psychology_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0, theme),
                _buildDot(1, theme),
                _buildDot(2, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.3 + (index * 0.2)),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildInput(ThemeData theme, bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Ask about your spending...',
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF18181B)
                    : const Color(0xFFF4F4F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send_rounded),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
