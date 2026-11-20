import 'package:flutter/material.dart';
/// 权限确认：✅纯 Flutter。选项 allow_once/allow_always/reject_once/reject_always。
class PermissionCard extends StatelessWidget {
  final String title;
  final ValueChanged<String>? onSelected;
  const PermissionCard(this.title, {super.key, this.onSelected});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(10), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Wrap(children: [
          for (final opt in const ['allow_once', 'allow_always', 'reject_once', 'reject_always'])
            Padding(padding: const EdgeInsets.only(right: 6),
              child: OutlinedButton(onPressed: () => onSelected?.call(opt), child: Text(opt))),
        ]),
      ],
    )),
  );
}
