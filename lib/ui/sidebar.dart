import 'package:flutter/material.dart';

/// 左侧栏占位（帖子/消息/设置）。
class Sidebar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const Sidebar({super.key, required this.selected, required this.onSelect});

  static const items = ['对话', '消息', '设置'];

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selected,
      onDestinationSelected: onSelect,
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(icon: Icon(Icons.chat_bubble_outline), label: Text('对话')),
        NavigationRailDestination(icon: Icon(Icons.message_outlined), label: Text('消息')),
        NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: Text('设置')),
      ],
    );
  }
}
