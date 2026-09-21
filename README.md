# HookLab

[![CI](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml/badge.svg)](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-JS%20%7C%20Wasm%20%7C%20Native-blue)](https://www.moonbitlang.com/)

HookLab 是一个用 MoonBit 编写的自托管 Webhook 安全与事件交付平台。它把最容易出事故的环节——**原始负载验签、时间窗校验、防重放、SQLite 事务持久化、路由、受限转换、应用事件发布、出站签名、Worker 租约、可靠重试、死信与回放**——放进一条可测试、可运行的处理流水线。

它既适合比赛演示，也解决真实工程问题：第三方回调“为什么验签失败”、同一事件“为什么执行两次”、失败请求“如何安全复现”、下游暂时不可用“如何重试而不制造重复副作用”。核心实现不依赖云服务，MoonBit 代码可以编译到 JS、Wasm、Wasm-GC 和 Native。

## 运行事件交付网关

推荐先校验版本化配置，再从环境变量读取密钥启动网关：

```bash
export HOOKLAB_SECRET=local-secret
moon run --target js cmd/hooklab -- config-check examples/gateway/config.json
moon run --target js cmd/hooklab -- serve-config examples/gateway/config.json
```

配置文件可以声明入站提供方、内容路由，也可以声明出站应用、端点和订阅，但拒绝保存明文密钥。打开 `http://127.0.0.1:8787/` 查看控制台，向 `POST /hooks/generic-hmac` 接收入站事件，或通过经过 Bearer 鉴权及幂等保护的发布 API 发送应用事件。网关在同一 SQLite 事务中保存事件和全部投递任务，使用带 fencing 的 Worker 租约处理崩溃接管。完整字段说明见 [配置文档](docs/CONFIGURATION.md)、[出站发布文档](docs/OUTBOUND.md) 和 [Gateway 运维文档](docs/GATEWAY.md)。

出站闭环示例：

```bash
export HOOKLAB_SECRET=ingress-development-secret
export HOOKLAB_PUBLISH_ORDERS=publisher-development-token
export HOOKLAB_SIGN_WAREHOUSE=endpoint-development-secret
moon run --target js cmd/hooklab -- serve-config examples/gateway/outbound-config.json

curl -X POST http://127.0.0.1:8787/api/outbound/applications/orders/events/order.created \
  -H 'Authorization: Bearer publisher-development-token' \
  -H 'Idempotency-Key: order-42-created' \
  -H 'Content-Type: application/json' \
  --data '{"order_id":"order-42"}'
```

临时演示仍可直接传入目标：

```bash
moon run --target js cmd/hooklab -- serve generic local-secret http://127.0.0.1:9090/target 8787 .hooklab-data
```

## 30 秒上手

环境要求：MoonBit CLI。普通 JS CLI 命令支持 Node.js 18+；运行内置 SQLite 网关需要 Node.js 24+。

```bash
moon test
moon run --target js cmd/hooklab -- retry-plan 5
moon run --target js cmd/hooklab -- sign github test-secret @examples/github/payload.json
```

上一条命令会给出 GitHub 风格的 `sha256=...`。复制它进行验证：

```bash
moon run --target js cmd/hooklab -- verify github test-secret @examples/github/payload.json 'sha256=<digest>'
```

生成不依赖网络的诊断页：

```bash
moon run --target js cmd/hooklab -- report github test-secret @examples/github/payload.json 'sha256=<digest>' diagnosis.html
```

直接向测试接收端重放；仅在你拥有或明确获准测试的 URL 上使用：

```bash
moon run --target js cmd/hooklab -- replay http://127.0.0.1:8787/webhook @examples/github/payload.json
```

## 能力

| 能力 | 实现 |
|---|---|
| 多平台验签 | GitHub、Stripe、飞书/Lark、通用 HMAC-SHA256 |
| 密码学 | 纯 MoonBit SHA-256、HMAC-SHA256、常量时间摘要比较 |
| 防重放 | 时间容差、未来时钟偏差、delivery ID TTL 幂等记录 |
| 内容路由 | JSON 点路径的 equals / not-equals / exists / contains / starts-with / ends-with |
| 声明式配置 | 版本化 JSON、全量错误报告、环境变量密钥和命名路由 |
| 规则化转换 | 按路由 set / remove / copy，显式输入、输出与操作数预算 |
| 隐私保护 | 嵌套 JSON 字段和 HTTP 头大小写不敏感脱敏 |
| 可复现诊断 | 无密钥 replay fixture、机器可读 JSON、单文件离线 HTML |
| 持久化网关 | 回环 HTTP 接收、SQLite WAL、进程重启恢复 |
| 事务存储 | Node 内置 SQLite、WAL、事件与投递原子提交、旧 `state.json` 一次性迁移 |
| 出站发布 | 配置化应用、端点和订阅，Bearer 发布鉴权、内容指纹幂等冲突检查 |
| 出站签名 | 每端点 HMAC-SHA256、公开 key ID、精确正文签名、重试保持稳定消息 ID |
| Worker 租约 | 原子领取、执行中续租、租约过期接管、owner/token/version fencing、崩溃恢复 |
| 投递状态机 | pending / scheduled / in-flight / delivered / dead-lettered / cancelled |
| 可靠交付 | 有界指数退避、Retry-After、死信恢复、事件回放 |
| 目标限流 | 每目标并发与滑动一秒速率控制、进程级 16 路硬上限；重试和回放同样受限 |
| 故障熔断 | 可选的按目标失败阈值、冷却与单次半开探测；其他目标继续投递 |
| 耗时统计 | 管理 API 提供不含目标 URL 或正文的匿名固定桶聚合指标 |
| 契约测试 | 提供方、事件类型、Header、JSON 路径、大小限制的全量问题报告 |
| 管理界面 | 脱敏事件 API、投递状态 API、本地 Web 控制台 |
| CLI | sign、verify/inspect、report、route-test、contract-check、config-check、retry-plan、replay、serve、serve-config |

## 设计边界

- 必须对收到的**原始请求体**验签，不能先解析再序列化。
- 路由转换只在验签成功后执行，并在幂等记录和持久化前原子完成；它不执行脚本、模板或网络调用。
- 密钥不会写入 fixture、报告或日志；诊断结果只保存脱敏内容。
- 核心库提供确定性内存语义，内置 Node 网关使用 SQLite WAL 和事务。它支持同一主机、同一数据库上的竞争领取，但跨主机高可用仍需要 PostgreSQL 等共享数据库适配器。
- CLI 的 replay 是显式调试操作，不会绕过目标服务认证；它不会转发原始提供方签名，目标端应使用隔离的测试入口。
- 投递领取与幂等由 SQLite 协调；限流、可选熔断和耗时指标仍仅在单个进程内生效，重启后计数清零，多实例全局配额需要外部协调。
- 出站端点目前是受信任的启动配置。启用租户自助配置前必须增加 DNS 重绑定、私网地址、云元数据地址和重定向防护。
- 当前按 UTF-8 文本处理请求体。任意二进制负载应在接入层保留原始字节后扩展 `WebhookRequest`。

运行网关见 [docs/GATEWAY.md](docs/GATEWAY.md)，出站发布与验签见 [docs/OUTBOUND.md](docs/OUTBOUND.md)，声明式配置见 [docs/CONFIGURATION.md](docs/CONFIGURATION.md)，规则化转换见 [docs/TRANSFORMS.md](docs/TRANSFORMS.md)，契约验证见 [docs/CONTRACTS.md](docs/CONTRACTS.md)，架构与扩展点见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，提供方协议见 [docs/PROVIDERS.md](docs/PROVIDERS.md)，威胁模型见 [SECURITY.md](SECURITY.md)，性能基线见 [BENCHMARK.md](BENCHMARK.md)，后续路线见 [docs/ROADMAP.md](docs/ROADMAP.md)，九月新增范围见 [docs/SEPTEMBER_SCOPE.md](docs/SEPTEMBER_SCOPE.md)。

## 项目结构

```text
hooklab/core       领域模型与稳定错误码
hooklab/crypto     SHA-256 / HMAC-SHA256
hooklab/providers  提供方验签适配器
hooklab/engine     幂等、路由、脱敏、重试、fixture
hooklab/event      接收事件模型与查询存储
hooklab/delivery   投递状态机、队列、重试和死信恢复
hooklab/outbound   应用发布、订阅匹配、确定性 ID、出站签名与验签
hooklab/contract   Webhook 契约验证
hooklab/config     版本化网关配置解析与全量校验
hooklab/transform  带显式预算的确定性 JSON 转换
hooklab/gateway    验签到持久化投递的领域编排
hooklab/pipeline   安全处理顺序
hooklab/report     JSON 与离线 HTML 诊断
cmd/hooklab        JS/Node CLI、本地网关与控制台
examples           可复现实例
```

## 验证

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --deny-warn
node scripts/gateway-e2e.mjs
node scripts/gateway-config-e2e.mjs
node scripts/gateway-limits-e2e.mjs
node scripts/gateway-circuit-e2e.mjs
node scripts/gateway-deadletter-e2e.mjs
node scripts/gateway-restart-e2e.mjs
node scripts/gateway-outbound-e2e.mjs
node scripts/gateway-lease-e2e.mjs
```

项目采用 MIT 许可。
