import '../models/auth.dart';
import '../models/phone_binding.dart';
import '../util/app_logger.dart';
import 'auth_repository.dart';
import '../network/endpoints.dart';

/// 扫码拿到 token 之后的"回调校验"结果。
/// - allowed：放行，携带 token 进入主界面；
/// - blocked：拦截，携带绑定页 URL 与提示文案，UI 引导去网页绑定后重新扫码。
abstract class PostLoginOutcome {
  const PostLoginOutcome();
}

class PostLoginAllowed extends PostLoginOutcome {
  final AuthTokens tokens;
  final PhoneBinding binding;
  const PostLoginAllowed(this.tokens, this.binding);
}

class PostLoginBlocked extends PostLoginOutcome {
  final PhoneBinding binding;
  final String bindUrl;
  final String message;
  const PostLoginBlocked(this.binding, this.bindUrl, this.message);
}

/// 可插拔的登录后校验器（未来可扩展实名/风控等校验）。
abstract class PostLoginChecker {
  Future<PostLoginOutcome> check(AuthTokens tokens);
}

/// 手机号绑定校验：账号未绑定手机号时禁止使用。
/// unknown 策略由 [blockOnUnknown] 控制：
/// - false（默认，兼容层保守）：接口未坐实时放行，避免误伤真实用户；
/// - true：严格模式，无法判定也拦截（动态抓包坐实接口后建议开启）。
class PhoneBindingChecker implements PostLoginChecker {
  final AuthRepository repo;
  final EnvConfig env;
  final bool blockOnUnknown;
  final String Function(String website)? _bindUrlBuilder;

  PhoneBindingChecker({
    required this.repo,
    EnvConfig? env,
    this.blockOnUnknown = false,
    String Function(String website)? bindUrlBuilder,
  })  : env = env ?? const EnvConfig(WorkbuddyEnv.prod),
        _bindUrlBuilder = bindUrlBuilder;

  /// 网页端手机号绑定入口。静态未坐实精确路径，用账号域安全设置页兜底。
  String bindUrl() {
    final base = _bindUrlBuilder?.call(env.website) ??
        '${env.website}/console/settings/security';
    return base;
  }

  @override
  Future<PostLoginOutcome> check(AuthTokens tokens) async {
    final log = AppLogger.instance;
    PhoneBinding binding;
    try {
      log.i('BIND_CHECK', '扫码成功，开始手机号绑定回调校验');
      final resp = await repo.fetchAccountProfile(tokens);
      binding = parsePhoneBinding(resp);
      log.i(
        'BIND_CHECK',
        '绑定状态=${binding.statusName}, 依据=${binding.reason}, '
        'rawCode=${binding.rawCode}, phone=${binding.phone}',
      );
    } catch (e, st) {
      log.e('BIND_CHECK', '绑定状态查询异常，按 unknown 处理: $e', e, st);
      binding = PhoneBinding(
        PhoneBindingStatus.unknown,
        reason: '查询异常: $e',
      );
    }

    if (binding.isBound) {
      return PostLoginAllowed(tokens, binding);
    }

    if (binding.isUnbound || blockOnUnknown) {
      final url = bindUrl();
      log.w('BIND_CHECK',
          '拦截登录：绑定状态=${binding.statusName}，引导去网页绑定 $url');
      return PostLoginBlocked(
        binding,
        url,
        '当前账号未绑定手机号，暂无法使用。请先前往网页完成手机号绑定，然后重新扫码登录。',
      );
    }

    // unknown 且非严格模式：放行但告警。
    log.w('BIND_CHECK',
        '绑定状态无法判定且未开启严格拦截，放行（需动态抓包坐实接口后开启 blockOnUnknown）');
    return PostLoginAllowed(tokens, binding);
  }
}
