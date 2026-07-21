# Shizuku 授权状态修复计划

1. 在 `PhoneControlMethodChannel` 增加权限状态模型和结果监听器；`requestShizuku` 对已授权、未运行、请求中和被拒绝返回明确状态。
2. 新增 Flutter `EventChannel` 客户端，接收原生 Shizuku 状态变化；保留现有手动 `getStatus` 作为兜底。
3. 让 `PhoneControlPage` 监听应用生命周期。页面恢复、收到原生事件和点击重新检查时刷新状态；授权中禁用重复请求并展示等待状态与错误提示。
4. 添加 Dart 测试覆盖状态文字和授权请求结果转换；运行静态检查与 Android Kotlin 编译。
5. 版本升至 `1.35`，构建双 ABI Release APK，验证签名后同步 GitHub 与 OpenList 更新清单。
