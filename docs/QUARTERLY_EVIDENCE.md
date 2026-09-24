# HookLab 季度评选：可复现证据与边界

本页把九月新增的 PostgreSQL 事件交付能力放进一个可以独立运行的合成场景。它是评审和维护测试材料，**不是**真实用户案例、第三方测评或生产性能承诺。八月已有的验签工具能力与九月新增范围见 [SEPTEMBER_SCOPE.md](SEPTEMBER_SCOPE.md)，完整启动与安全说明见 [PLATFORM.md](PLATFORM.md)。

## 已备好环境后的演示流程

场景：订单系统发布 `order.created`，仓库消费者接收签名事件。脚本在本机回环地址建立两个平台实例和一个模拟消费者，只连接明确指定的专用 PostgreSQL 测试库，不向外网发请求。

1. 注册租户、应用、端点、订阅和要求 CloudEvents 的订单契约；故意发布类型错误的 `orderId`，断言返回 422 且数据库没有事件。
2. 发布有效订单。第一个 Worker 已领取任务并把请求发往模拟消费者后，脚本强制终止该 Worker；第二个实例在租约过期后接管同一交付。
3. 断言最终状态是 `delivered`、投递 ID 没有改变、网络上看到了两次尝试，而数据库只记录成功接管后的完成尝试。这展示 **at least once** 与消费者去重的必要性，不是 exactly once。
4. 并发发布 32 条合成订单事件，记录本机发布请求的 p50/p95 和整批完成耗时；再断言错误管理令牌无权访问租户目录。

准备 Node.js 24+、MoonBit CLI 和独立 PostgreSQL 17 数据库，先在仓库根目录运行 `npm ci --ignore-scripts`。数据库名必须为 `hooklab_test` 或 `hooklab_test_` 后接小写字母/数字；脚本不删表、不清除已有记录，但会写入随机命名的合成租户，因此不要使用共享或生产数据库。

Linux/macOS：

```bash
export TEST_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/hooklab_test'
node scripts/platform-showcase.mjs
```

Windows PowerShell：

```powershell
$env:TEST_DATABASE_URL = 'postgresql://postgres:postgres@127.0.0.1:5432/hooklab_test'
node scripts/platform-showcase.mjs
```

脚本打印 JSON 测试摘要，包含 `contract_rejection_without_persistence`、`failover` 和 `local_sample`。**应看通过的断言，不应期待固定毫秒数。** 接管时间包含默认 30 秒租约等待；批量耗时受机器、数据库和 CI 负载影响，仅用于在同样环境和版本下观察回归，不可外推真实吞吐量或 SLO。[CI 工作流](../.github/workflows/ci.yml)在 PostgreSQL 17 上自动运行常规双 Worker 测试和这套故障演示。公开 CI 日志提供复核入口；本文件不填写尚未实测的性能数字。

一次已核实的样本：[2026-09-24 主分支 CI，提交 `80e78ea`](https://github.com/bzhangui/hooklab/actions/runs/36007818373)，运行环境为 GitHub Actions `ubuntu-24.04`、Node.js 24、PostgreSQL 17，模拟消费者在本机回环地址。非法事件未入库；故障前后同一投递 ID 被网络请求两次，接管后状态为 `delivered`，从强制终止到完成约 **30,138 ms**。随后 32 个并发发布请求的单次请求耗时 p50 为 **103 ms**、p95 为 **117 ms**，整批事件在 **322 ms** 内全部投递完成。以上是单次 CI 合成样本，不是容量上限、生产吞吐量或用户侧延迟保证；任何后续版本都应重新运行并保留原始日志。

## MoonBit 与 Node.js 的实际职责

| 环节 | 主要实现 | 可核查位置 |
|---|---|---|
| 事件契约校验、订阅投递计划、出站签名、重试决策 | MoonBit 领域内核 | [`platform_common.mbt`](../cmd/hooklab/platform_common.mbt)、[`event_schema.mbt`](../hooklab/contract/event_schema.mbt)、[`outbound.mbt`](../hooklab/outbound/outbound.mbt) |
| HTTP、PostgreSQL 事务、租户与角色 API、Worker 领取与网络传输 | Node.js 运行时适配器 | [`server.cjs`](../platform/server.cjs)、[`worker.cjs`](../platform/worker.cjs) |
| 统一启动与 MoonBit 回调绑定 | MoonBit JS 目标及薄适配层 | [`platform_runtime_js.mbt`](../cmd/hooklab/platform_runtime_js.mbt) |

因此“MoonBit 为主”指整个仓库的可移植领域能力由 MoonBit 承担，**不表示** PostgreSQL 控制面或网络 I/O 已由 MoonBit 原生实现。评审可通过跨目标 `moon check/test/build`、平台单元测试和 PostgreSQL E2E 分别验证这两层。九月新增功能不应全部归功于 MoonBit，架构取舍也不能用代码行数代替解释。

## 可核查交付物与尚缺证据

- 源码、连续提交、README、MIT 许可证、第三方声明、测试与 CI 均在公开仓库；[CHANGELOG.md](../CHANGELOG.md)与[九月范围说明](SEPTEMBER_SCOPE.md)区分旧基础和新增工作。
- [PLATFORM.md](PLATFORM.md)给出完整 API 和运行步骤；[SECURITY.md](../SECURITY.md)列出威胁模型，README 明列两种部署模式及不能混用的存储边界。
- 暂无可公开核实的外部用户、生产部署或长期线上 SLO 数据，因此不宣称已取得这些成效。评审若要求真实落地证据，应另外提供经用户授权、脱敏且可验证的使用记录。
- PostgreSQL 模式尚缺跨实例全局配额/限流、数据库级 RLS、自动 TLS、SQLite 迁移和高可用部署；演示不能替代这些生产加固工作。具体限制以[平台文档](PLATFORM.md)为准。
