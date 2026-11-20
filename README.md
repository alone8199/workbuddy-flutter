# WorkBuddy Flutter（Windows）

WorkBuddy 客户端的 Flutter 重写版本，目标平台为 Windows。当前实现包含：

- 网络层：多环境 Dio 封装、请求头对齐、指数退避重试、401 刷新、Cookie 与 ACP（Streamable HTTP）传输
- 认证层：多方式登录状态机、token 安全存储与并发刷新
- 对话层：会话管理、SSE 流式解析、消息状态机、中断与重连
- 渲染层：Markdown/代码块/工具卡片/交互式消息等消息类型渲染

## 环境

- Flutter 3.7.12（stable）
- Dart 2.19.6
- 目标平台：Windows desktop

> 该版本较旧，CI 固定使用 `windows-2022`（VS2022）以避免 windows-latest 的工具链兼容问题。

## 本地构建

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
```

产物位于 `build/windows/runner/Release/`。

## 测试与分析

```powershell
flutter analyze
flutter test
```

## CI

`.github/workflows/build-windows.yml` 在推送到 `main`/`master`、PR 或手动触发时，
在 Windows runner 上执行 pub get → analyze → build windows，并上传 release 压缩包作为 artifact。
