import 'package:flutter/material.dart';

/// AI 交互式消息卡片：主动提问 / 要求确认 / 单选 / 多选 / 权限确认。
/// 数据源：报告02 §5（permission 4 选项、elicitation form/url、askuserquestion）。
/// 用户回应通过 [onRespond] 回传（由 controller 经 JSON-RPC response 发回服务端）。
class InteractiveCard extends StatefulWidget {
  final String? method;
  final String message;
  final String? mode; // 'form' | 'url' | 'permission' | 'choice'
  final List<PermissionOption>? options;
  final List<String>? choices;
  final bool multiSelect;
  final Map<String, dynamic>? requestedSchema;
  final ValueChanged<InteractiveResponse> onRespond;
  const InteractiveCard({
    super.key,
    this.method,
    required this.message,
    this.mode,
    this.options,
    this.choices,
    this.multiSelect = false,
    this.requestedSchema,
    required this.onRespond,
  });

  @override
  State<InteractiveCard> createState() => _InteractiveCardState();
}

class PermissionOption {
  final String optionId;
  final String name;
  final String kind; // allow_once/allow_always/reject_once/reject_always
  PermissionOption({required this.optionId, required this.name, required this.kind});

  factory PermissionOption.fromJson(Map<String, dynamic> j) => PermissionOption(
        optionId: j['optionId']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        kind: j['kind']?.toString() ?? '',
      );
}

/// 用户回应：权限选 optionId；choice 选值；form 带表单值；或 cancelled。
class InteractiveResponse {
  final String outcome; // 'selected' | 'cancelled' | 'accept' | 'decline'
  final String? optionId;
  final List<String>? values;
  final Map<String, dynamic>? formValues;
  const InteractiveResponse({
    required this.outcome,
    this.optionId,
    this.values,
    this.formValues,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'outcome': outcome,
        if (optionId != null) 'optionId': optionId,
        if (values != null) 'values': values,
        if (formValues != null) 'values': formValues,
      };
}

class _InteractiveCardState extends State<InteractiveCard> {
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _fields = {};
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('已提交回应', style: TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.help_outline, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(widget.message, style: const TextStyle(fontSize: 14))),
          ]),
          const SizedBox(height: 8),
          if (widget.options != null) _permissionOptions(),
          if (widget.choices != null) _choices(),
          if (widget.mode == 'form' && widget.requestedSchema != null) _form(),
          if (widget.mode == 'url') _urlMode(),
          if (widget.method == null &&
              widget.options == null &&
              widget.choices == null &&
              widget.requestedSchema == null)
            Row(children: [
              OutlinedButton(onPressed: () => _respond(const InteractiveResponse(outcome: 'accept')),
                  child: const Text('确定')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _respond(const InteractiveResponse(outcome: 'decline')),
                  child: const Text('取消')),
            ]),
        ]),
      ),
    );
  }

  Widget _permissionOptions() {
    return Wrap(
      spacing: 6,
      children: [
        for (final o in widget.options!)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: OutlinedButton(
              onPressed: () => _respond(InteractiveResponse(
                  outcome: 'selected', optionId: o.optionId)),
              child: Text(o.name.isNotEmpty ? o.name : o.kind, style: const TextStyle(fontSize: 12)),
            ),
          ),
      ],
    );
  }

  Widget _choices() {
    return Column(children: [
      for (final c in widget.choices!)
        CheckboxListTile(
          value: _selected.contains(c),
          title: Text(c, style: const TextStyle(fontSize: 13)),
          onChanged: (v) => setState(() {
            if (widget.multiSelect) {
              if (v == true) {
                _selected.add(c);
              } else {
                _selected.remove(c);
              }
            } else {
              _selected
                ..clear()
                ..add(c);
            }
          }),
        ),
      ElevatedButton(
        onPressed: _selected.isEmpty
            ? null
            : () => _respond(InteractiveResponse(
                outcome: 'accept', values: _selected.toList())),
        child: const Text('提交'),
      ),
    ]);
  }

  Widget _form() {
    final props = widget.requestedSchema!['properties'];
    if (props is! Map) return const Text('[无法解析表单]');
    return Column(children: [
      for (final entry in props.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextField(
            decoration: InputDecoration(labelText: entry.key.toString()),
            controller: _fields.putIfAbsent(
                entry.key.toString(), () => TextEditingController()),
          ),
        ),
      ElevatedButton(
        onPressed: () => _respond(InteractiveResponse(
            outcome: 'accept',
            formValues: _fields.map((k, v) => MapEntry(k, v.text)))),
        child: const Text('提交'),
      ),
    ]);
  }

  Widget _urlMode() => OutlinedButton.icon(
        onPressed: () => _respond(const InteractiveResponse(outcome: 'accept')),
        icon: const Icon(Icons.open_in_new),
        label: const Text('打开链接'),
      );

  void _respond(InteractiveResponse r) {
    setState(() => _submitted = true);
    widget.onRespond(r);
  }
}

