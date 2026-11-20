import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message.dart';
import 'message_accumulator.dart';

/// 多会话状态管理：每个 sessionId 持有独立 accumulator 与工具表，
/// 切换会话不串消息（报告05 多会话语义）。
class ConversationStore {
  final Map<String, MessageAccumulator> _accs = {};
  String? _activeSessionId;

  String? get activeSessionId => _activeSessionId;

  MessageAccumulator accumulator(String sessionId) =>
      _accs.putIfAbsent(sessionId, () => MessageAccumulator());

  MessageAccumulator get active =>
      _activeSessionId != null ? accumulator(_activeSessionId!) : MessageAccumulator();

  void activate(String sessionId) => _activeSessionId = sessionId;

  void dispose(String sessionId) => _accs.remove(sessionId);

  List<ChatMessage> messagesOf(String sessionId) => accumulator(sessionId).messages;
}

/// 全局会话存储（Riverpod）。
final conversationStoreProvider = Provider<ConversationStore>((ref) => ConversationStore());

/// 当前激活会话的消息列表（供 UI watch）。
final messagesProvider = StateNotifierProvider<ConversationNotifier, List<ChatMessage>>((ref) {
  final store = ref.watch(conversationStoreProvider);
  return ConversationNotifier(store);
});

class ConversationNotifier extends StateNotifier<List<ChatMessage>> {
  final ConversationStore store;
  MessageAccumulator? _bound;

  ConversationNotifier(this.store) : super(const []) {
    _bind();
  }

  void _bind() {
    final id = store.activeSessionId;
    _bound?.removeListener(_refresh);
    _bound = id != null ? store.accumulator(id) : null;
    _bound?.addListener(_refresh);
    _refresh();
  }

  void _refresh() {
    state = _bound != null ? List.unmodifiable(_bound!.messages) : const [];
  }

  /// 切换会话后调用，重新绑定监听器。
  void rebind() => _bind();
}
