import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/stream_parser.dart';
import '../models/chat_models.dart';
import '../models/provider_config.dart';
import '../providers/chat_provider.dart';
import '../providers/wiki_source.dart';
import '../theme/app_theme.dart';

/// Full chat parity with the web app's Ask.tsx: provider/model picker
/// (fetched live from the connected endpoint's /models/config, exactly the
/// data UserSelector.tsx reads), Deep Research toggle, 🔐 Security-context
/// toggle, streaming answers. Only ever shown for a ServerWikiSource
/// (WikiSource.canChat) -- a standalone bundle has no LLM backend attached.
class ChatScreen extends StatelessWidget {
  final WikiSource source;
  final String? currentPageId;
  const ChatScreen({super.key, required this.source, this.currentPageId});

  @override
  Widget build(BuildContext context) {
    final serverSource = source as ServerWikiSource;
    return ChangeNotifierProvider(
      create: (_) => ChatProvider(
        endpoint: serverSource.endpoint,
        sourceId: source.sourceId,
        repoUrl: serverSource.project.repoType == 'website'
            ? 'https://${serverSource.project.repo}'
            : serverSource.wikiCacheData['repo_url'] as String? ?? '',
        repoType: serverSource.project.repoType,
        owner: serverSource.project.owner,
        repo: serverSource.project.repo,
        language: serverSource.project.language,
        currentPageId: currentPageId,
      ),
      child: _ChatScreenBody(client: serverSource.client),
    );
  }
}

class _ChatScreenBody extends StatefulWidget {
  final dynamic client; // HackDeepWikiClient
  const _ChatScreenBody({required this.client});

  @override
  State<_ChatScreenBody> createState() => _ChatScreenBodyState();
}

class _ChatScreenBodyState extends State<_ChatScreenBody> {
  final _controller = TextEditingController();
  ModelsConfig? _config;

  @override
  void initState() {
    super.initState();
    widget.client.getModelsConfig().then((ModelsConfig cfg) {
      if (!mounted) return;
      setState(() => _config = cfg);
      final chat = context.read<ChatProvider>();
      chat.setProvider(cfg.defaultProvider);
      chat.setModel(cfg.providerById(cfg.defaultProvider)?.models.firstOrNull?.id);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(icon: const Icon(Icons.add_comment_outlined), onPressed: chat.newChat, tooltip: 'New chat'),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(context, chat),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final m in chat.activeSession.messages) _MessageBubble(message: m),
                if (chat.isLoading)
                  _MessageBubble.streaming(text: chat.streamingAnswer, events: chat.streamingEvents),
                if (chat.error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Error: ${chat.error}', style: TextStyle(color: Theme.of(context).appColors.highlight)),
                  ),
              ],
            ),
          ),
          _buildComposer(context, chat),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, ChatProvider chat) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_config != null)
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: chat.provider,
                    items: [
                      for (final p in _config!.providers) DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      chat.setProvider(v);
                      chat.setModel(_config!.providerById(v)?.models.firstOrNull?.id);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: chat.model,
                    items: [
                      for (final m in _config!.providerById(chat.provider)?.models ?? const [])
                        DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: chat.setModel,
                  ),
                ),
              ],
            ),
          Row(
            children: [
              FilterChip(
                label: const Text('Deep Research'),
                selected: chat.deepResearch,
                onSelected: chat.setDeepResearch,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('🔐 Security context'),
                selected: chat.includeSecurityContext,
                onSelected: chat.setIncludeSecurityContext,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, ChatProvider chat) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: 'Ask about this wiki…'),
                onSubmitted: (_) => _send(chat),
                enabled: !chat.isLoading,
              ),
            ),
            IconButton(
              icon: chat.isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              onPressed: chat.isLoading ? null : () => _send(chat),
            ),
          ],
        ),
      ),
    );
  }

  void _send(ChatProvider chat) {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    chat.sendMessage(text);
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _MessageBubble extends StatelessWidget {
  final String role;
  final String text;

  _MessageBubble({required ChatMessage message})
      : role = message.role,
        text = message.content;

  const _MessageBubble.streaming({required this.text, required List<ProcessEvent> events})
      : role = 'assistant';

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final colors = Theme.of(context).appColors;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? colors.accentPrimary.withValues(alpha: 0.15) : colors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderColor),
        ),
        child: Text(text.isEmpty ? '…' : text),
      ),
    );
  }
}
