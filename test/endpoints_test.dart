import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/network/endpoints.dart';

void main() {
  test('桌面认证接口走 product endpoint + /v2/plugin 前缀', () {
    const env = EnvConfig(WorkbuddyEnv.prod);
    expect(env.endpoint, 'https://www.workbuddy.cn');
    expect(env.deviceAuthCode,
        'https://www.workbuddy.cn/v2/plugin/device/auth/code');
    expect(env.authState('workbuddy'),
        'https://www.workbuddy.cn/v2/plugin/auth/state?platform=workbuddy');
    expect(env.authToken('ST-1'),
        'https://www.workbuddy.cn/v2/plugin/auth/token?state=ST-1');
    expect(env.authRefresh,
        'https://www.workbuddy.cn/v2/plugin/auth/token/refresh');
    expect(env.authHandoff,
        'https://www.workbuddy.cn/v2/plugin/auth/handoff/token');
  });

  test('账号域 authz 接口仍走 oauth2 域（未被误改）', () {
    const env = EnvConfig(WorkbuddyEnv.prod);
    expect(env.oauth2, 'https://oauth2.account.tencent.com');
  });
}
