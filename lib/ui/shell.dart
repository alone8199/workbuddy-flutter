import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_manager.dart';
import '../network/client.dart';
import '../network/acp_client.dart';
import '../chat/session/session_repository.dart';
import '../chat/conversation_state.dart';
import '../chat/chat_controller.dart';
import 'sidebar.dart';
import 'chat_page.dart';

/// 主壳：左侧栏 + 右侧内容区 + 顶部登录状态指示。
/// 「对话」页接入真实对话链路（ACP → session/* → SSE → 渲染）。
class AppShell extends ConsumerStatefulWidget {
  final TokenManager tokenManager;
  final NetworkClient network;
  const AppShell({super.key, required this.tokenManager, required this.network});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selected = 0;
  late final AcpClient _acp;
  late final SessionRepository _sessions;
  late final ConversationStore _store;
  late final ChatController _chat;

  @override
  void initState() {
    super.initState();
    _acp = AcpClient(widget.network);
    _sessions = SessionRepository(transport: _acp, cwd: '');
    _store = ConversationStore();
    _chat = ChatController(transport: _acp, sessions: _sessions, store: _store);
  }

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = widget.tokenManager.isLoggedIn;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WorkBuddy Flutter'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(loggedIn ? Icons.cloud_done : Icons.cloud_off, size: 16,
                color: loggedIn ? Colors.green : Colors.grey),
              const SizedBox(width: 6),
              Text(loggedIn ? '已登录' : '未登录', style: const TextStyle(fontSize: 13)),
            ]),
          ),
        ],
      ),
      body: Row(
        children: [
          Sidebar(selected: _selected, onSelect: (i) => setState(() => _selected = i)),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selected == 0
                ? ChatPage(controller: _chat, store: _store)
                : Center(
                    child: Text(Sidebar.items[_selected],
                        style: Theme.of(context).textTheme.headlineMedium),
                  ),
          ),
        ],
      ),
    );
  }
}
