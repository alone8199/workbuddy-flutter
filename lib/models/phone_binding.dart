/// 手机号绑定状态（扫码登录"回调校验"用）。
///
/// 业务约束：账号未绑定手机号时不可使用（提示去网页绑定后重新扫码）。
/// 由于逆向阶段未坐实"查询是否绑定手机号"的专用接口，这里把判定做成
/// 纯函数解析 + 三种状态，接口未坐实时落到 unknown，由上层决定放行或拦截。
enum PhoneBindingStatus {
  bound, // 已绑定，允许使用
  unbound, // 明确未绑定，禁止使用
  unknown, // 响应/接口未坐实，无法判定
}

class PhoneBinding {
  final PhoneBindingStatus status;
  final String? phone; // 脱敏手机号（仅日志）
  final String? rawCode; // 服务端原始业务码
  final String? reason; // 判定依据

  const PhoneBinding(
    this.status, {
    this.phone,
    this.rawCode,
    this.reason,
  });

  bool get isBound => status == PhoneBindingStatus.bound;
  bool get isUnbound => status == PhoneBindingStatus.unbound;
  bool get isUnknown => status == PhoneBindingStatus.unknown;

  /// 避免依赖 enum.name（Dart 2.19 兼容性稳妥）。
  String get statusName => _statusName(status);

  static String _statusName(PhoneBindingStatus s) {
    switch (s) {
      case PhoneBindingStatus.bound:
        return 'bound';
      case PhoneBindingStatus.unbound:
        return 'unbound';
      case PhoneBindingStatus.unknown:
        return 'unknown';
    }
  }
}

/// 手机号脱敏：只保留前 3 后 4。
String maskPhone(String raw) {
  final s = raw.trim();
  if (s.length <= 7) return s;
  return '${s.substring(0, 3)}****${s.substring(s.length - 4)}';
}

/// 从账号信息响应中解析手机号绑定状态（纯函数，可单测）。
///
/// 判定优先级：
/// 1) code/msg 文本中的明确"未绑定手机号"信号；
/// 2) bool 字段（hasPhone/phoneBound/...）为 false → 未绑定，true → 已绑定；
/// 3) 手机号字符串字段非空 → 已绑定；
/// 4) 其余 → unknown（接口未坐实，交由上层策略）。
PhoneBinding parsePhoneBinding(dynamic body) {
  final root = (body is Map) ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  final data = (root['data'] is Map)
      ? Map<String, dynamic>.from(root['data'] as Map)
      : root;
  final merged = <String, dynamic>{...root, ...data};

  final code = merged['code']?.toString();
  final msg = merged['msg']?.toString() ??
      merged['message']?.toString() ??
      merged['errmsg']?.toString();
  final text = '${code ?? ''} ${msg ?? ''}'.toLowerCase();

  // 1) 明确的未绑定文案 / 业务码
  final unboundPattern = RegExp(
    r'phone[_-]?not[_-]?bound|need[_-]?bind[_-]?phone|mobile[_-]?not[_-]?bound|'
    r'bind[_-]?phone[_-]?required|no[_-]?bind[_-]?phone|phone[_-]?empty|'
    r'未绑定.{0,6}手机|手机.{0,6}未绑定|请绑定手机|需绑定手机|未绑手机号',
  );
  if (unboundPattern.hasMatch(text)) {
    return PhoneBinding(
      PhoneBindingStatus.unbound,
      rawCode: code,
      reason: '服务端提示未绑定手机号: ${msg ?? code}',
    );
  }

  const boolKeys = <String>[
    'hasPhone',
    'phoneBound',
    'bindPhone',
    'mobileBound',
    'hasMobile',
    'phoneBind',
  ];

  // 2a) bool 字段为 false → 未绑定
  for (final k in boolKeys) {
    final v = merged[k];
    if (v == false || v == 'false' || v == 0 || v == '0') {
      return PhoneBinding(
        PhoneBindingStatus.unbound,
        rawCode: code,
        reason: '字段 $k=false',
      );
    }
  }

  // 2b) bool 字段为 true → 已绑定
  for (final k in boolKeys) {
    final v = merged[k];
    if (v == true || v == 'true' || v == 1 || v == '1') {
      return PhoneBinding(
        PhoneBindingStatus.bound,
        rawCode: code,
        reason: '字段 $k=true',
      );
    }
  }

  // 3) 手机号字符串字段非空 → 已绑定
  const phoneKeys = <String>[
    'phone',
    'mobile',
    'bindMobile',
    'safePhone',
    'maskedPhone',
    'phoneNumber',
  ];
  for (final k in phoneKeys) {
    final v = merged[k];
    if (v is String && v.trim().isNotEmpty) {
      return PhoneBinding(
        PhoneBindingStatus.bound,
        phone: maskPhone(v),
        rawCode: code,
        reason: '字段 $k 非空',
      );
    }
  }

  // 4) 无法判定（接口未坐实）
  return PhoneBinding(
    PhoneBindingStatus.unknown,
    rawCode: code,
    reason: '响应缺少可判定的绑定字段（接口未坐实）',
  );
}
