# MoonBit 核心职责与可复核证据

HookLab 的 PostgreSQL 控制面和网络/数据库 I/O 由 Node.js 适配；可移植的事件决策由 MoonBit 包实现。这里不把 Node.js 代码冒称为 MoonBit。评审或维护者可以按以下调用链确认九月平台确实使用了 MoonBit 核心，而非仅把它作为仓库装饰。

| 平台行为 | MoonBit 决策位置 | Node.js 适配位置 | 核验入口 |
|---|---|---|---|
| 订阅匹配与投递计划 | `hooklab/outbound/outbound.mbt` 的 `plan_publication`，由 `cmd/hooklab/platform_common.mbt` 的 `platform_plan` 调用 | `platform/server.cjs` 读取租户订阅、事务落库 | `cmd/hooklab/platform_common_wbtest.mbt`、PostgreSQL E2E |
| 事件契约、CloudEvents 与兼容判定 | `hooklab/contract/event_schema.mbt`、`platform_validate`、`schema_compatible_json` | HTTP 和数据库版本记录在 `platform/server.cjs` | MoonBit 契约单测、非法事件 422 且未入库测试 |
| 出站签名 | `hooklab/outbound/outbound.mbt` 的 `sign_delivery` | `platform/worker.cjs` 组装 HTTP 请求 | 签名向量单测、容器接收端独立 HMAC 核对 |
| 重试/死信决策 | `cmd/hooklab/gateway_common.mbt` 的 `gateway_decision_json` 调用 `hooklab/engine` | Worker 领取、持久化、租约与网络传输在 Node.js | MoonBit 回调测试、真实 PostgreSQL 重试与故障接管测试 |

本地复核：

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --deny-warn
npm run test:platform
```

完整 PostgreSQL 双 Worker、故障接管和 Compose 签名重试测试在 `.github/workflows/ci.yml` 中运行。后者使用独立的 CI-only 接收端和回环测试开关；默认部署不允许任意私网目标。各测试验证的是功能与边界，不证明生产 SLO、外部用户采用或所有 PostgreSQL 版本兼容。

后续如增加新平台能力，应先判断它是可移植的确定性规则，还是与数据库/HTTP/容器紧耦合的 I/O。前者放入 MoonBit 并增加跨目标测试；后者留在薄适配层，同时保留端到端证据。单纯把 I/O 代码翻译成 MoonBit、却降低安全边界和可维护性，不作为目标。
