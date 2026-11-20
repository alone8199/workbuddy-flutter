import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_controller.dart';
import '../chat/conversation_state.dart';
import '../render/interactive/interactive_card.dart';
import '../render/render_dispatcher.dart';

/// 最简对话 UI：消息列表 + 输入框，能发能收能流式滚动。
class ChatPage extends ConsumerStatefulWidget {
  final ChatController controller;
  final ConversationStore store;
  const ChatPage({super.key, required this.controller, required this.store});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.onInteractiveRequest = (req) {
      // 交互式请求到达时刷新（控件本身由工具消息渲染；权限/elicitation 为独立卡片）。
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    _error = null;
    try {
      await widget.controller.send(text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);
    _scrollToBottom(); // 流式增量到达时自动滚底

    return Column(children: [
      if (_error != null)
        Container(
          color: Theme.of(context).colorScheme.errorContainer,
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12))),
            IconButton(icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _error = null)),
          ]),
        ),
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(12),
          itemCount: messages.length,
          // 用 message.id 作 key：流式增量只更新最后一条，不整条重建。
          itemBuilder: (context, i) {
            final m = messages[i];
            return RenderDispatcher(
              m,
              key: ValueKey(m.id),
              onInteractiveRespond: (r) => _onInteractive(r),
              onRetry: m.status.name == 'failed'
                  ? () => widget.controller.retry(m.id, m.content)
                  : null,
            );
          },
        ),
      ),
      const Divider(height: 1),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                decoration: const InputDecoration(
                  hintText: '输入消息…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 4,
                minLines: 1,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.controller.isBusy)
              IconButton(
                tooltip: '停止',
                icon: const Icon(Icons.stop_circle, color: Colors.red),
                onPressed: () => widget.controller.stop(),
              )
            else
              FloatingActionButton.small(
                onPressed: _send,
                child: const Icon(Icons.send),
              ),
          ]),
        ),
      ),
    ]);
  }

  void _onInteractive(InteractiveResponse r) {
    // 交互式回应：交给 controller 经 JSON-RPC response 发回服务端。
    widget.controller.respondInteractive(r.toJson());
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('已回应: ${r.outcome}'), duration: const Duration(seconds: 1)),
    );
  }
}
