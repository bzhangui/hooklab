# 验收矩阵

## 当前可验证基线

| 声明 | 触发方式 | 通过标准 | 状态 |
|---|---|---|---|
| 四目标可构建 | `moon build --target all --deny-warn` | 命令退出码为 0 | 已通过 |
| 四目标测试一致 | `moon test --target all` | 每个目标 22/22 | 已通过 |
| GitHub 官方向量 | providers 测试 | 固定签名验签成功 | 已通过 |
| 篡改检测 | providers 测试 | 修改 body 后拒绝 | 已通过 |
| 时间防重放 | providers 测试 | 过期和未来事件拒绝 | 已通过 |
| 幂等防重复 | engine/pipeline 测试 | TTL 内第二次处理拒绝 | 已通过 |
| 嵌套脱敏 | engine/report 测试 | 原敏感值不出现在输出 | 已通过 |
| HTML 注入防护 | report 测试 | 不可信内容被转义 | 已通过 |
| CLI 完整路径 | `scripts/demo.ps1` 或 `scripts/demo.sh` | 验签、路由、重试、报告均成功 | 已通过 |
| 远程持续集成 | GitHub Actions / CI | `main` 最新运行绿色 | 已通过 |

## 计划版本验收门禁

| 领域 | 必须提交的证据 |
|---|---|
| 字节与流式密码学 | 标准向量、随机分块等价性、大负载内存基准、四目标一致性 |
| provider 扩展 | 契约测试、格式错误、密钥轮换、官方文档链接和版本记录 |
| 持久化幂等 | 并发竞争、TTL、唯一约束和重启恢复集成测试 |
| 可靠交付 | 状态迁移表、可重试/永久失败分类、崩溃注入和死信恢复演示 |
| 网络安全 | allowlist、超时、大小限制、重定向策略与 SSRF 负向测试 |
| Web/CLI 一致性 | 同一 fixture 在两端生成相同状态码、路由和脱敏结果 |
| 用户体验 | 干净环境安装记录、5 分钟快速开始、错误修复建议和演示视频 |
| 可解释性 | 开发历程、AI 使用说明、ADR、性能/安全取舍与最终验收报告 |

## 发布前固定命令

```bash
moon info
moon fmt --check
moon check --target all --deny-warn
moon test --target all
moon build --target all --deny-warn
```

若任一命令失败、生成接口存在未解释变化、示例无法复现或报告泄露测试敏感值，则不得标记里程碑完成。
