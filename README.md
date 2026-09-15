# HookLab

[![CI](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml/badge.svg)](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-JS%20%7C%20Wasm%20%7C%20Native-blue)](https://www.moonbitlang.com/)

HookLab 是一个用 MoonBit 编写的自托管 Webhook 安全与事件交付平台。它把最容易出事故的环节——**原始负载验签、时间窗校验、防重放、持久化、路由、敏感字段脱敏、可靠重试、死信与回放**——放进一条可测试、可运行的处理流水线。

它既适合比赛演示，也解决真实工程问题：第三方回调“为什么验签失败”、同一事件“为什么执行两次”、失败请求“如何安全复现”、下游暂时不可用“如何重试而不制造重复副作用”。核心实现不依赖云服务，MoonBit 代码可以编译到 JS、Wasm、Wasm-GC 和 Native。

## 运行事件交付网关

推荐先校验版本化配置，再从环境变量读取密钥启动网关：

```bash
export HOOKLAB_SECRET=local-secret
moon run --target js cmd/hooklab -- config-check examples/gateway/config.json
moon run --target js cmd/hooklab -- serve-config examples/gateway/config.json
```

配置文件可以声明提供方、端口、数据目录和按 JSON 内容匹配的投递路由，但拒绝保存明文密钥。打开 `http://127.0.0.1:8787/` 查看控制台，向 `POST /hooks/generic-hmac` 发送事件。网关会原子保存状态，在临时错误后按指数退避重试，超过上限进入死信队列，并支持人工恢复。完整字段说明见 [配置文档](docs/CONFIGURATION.md) 和 [Gateway 运维文档](docs/GATEWAY.md)。

临时演示仍可直接传入目标：

```bash
moon run --target js cmd/hooklab -- serve generic local-secret http://127.0.0.1:9090/target 8787 .hooklab-data
```

## 30 秒上手

环境要求：MoonBit CLI，以及运行 CLI 所需的 Node.js 18+。

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
| 隐私保护 | 嵌套 JSON 字段和 HTTP 头大小写不敏感脱敏 |
| 可复现诊断 | 无密钥 replay fixture、机器可读 JSON、单文件离线 HTML |
| 持久化网关 | 回环 HTTP 接收、原子状态快照、进程重启恢复 |
| 投递状态机 | pending / scheduled / in-flight / delivered / dead-lettered / cancelled |
| 可靠交付 | 有界指数退避、Retry-After、死信恢复、事件回放 |
| 契约测试 | 提供方、事件类型、Header、JSON 路径、大小限制的全量问题报告 |
| 管理界面 | 脱敏事件 API、投递状态 API、本地 Web 控制台 |
| CLI | sign、verify/inspect、report、route-test、contract-check、config-check、retry-plan、replay、serve、serve-config |

## 设计边界

- 必须对收到的**原始请求体**验签，不能先解析再序列化。
- 密钥不会写入 fixture、报告或日志；诊断结果只保存脱敏内容。
- 核心库提供确定性内存存储，内置网关提供单节点原子文件快照。多实例生产环境仍应将相同的 `check-and-record` 和投递状态语义落到具备唯一约束及事务的数据库。
- CLI 的 replay 是显式调试操作，不会绕过目标服务认证；它不会转发原始提供方签名，目标端应使用隔离的测试入口。
- 当前按 UTF-8 文本处理请求体。任意二进制负载应在接入层保留原始字节后扩展 `WebhookRequest`。

运行网关见 [docs/GATEWAY.md](docs/GATEWAY.md)，声明式配置见 [docs/CONFIGURATION.md](docs/CONFIGURATION.md)，契约验证见 [docs/CONTRACTS.md](docs/CONTRACTS.md)，架构与扩展点见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，提供方协议见 [docs/PROVIDERS.md](docs/PROVIDERS.md)，威胁模型见 [SECURITY.md](SECURITY.md)，性能基线见 [BENCHMARK.md](BENCHMARK.md)，后续路线见 [docs/ROADMAP.md](docs/ROADMAP.md)，九月新增范围见 [docs/SEPTEMBER_SCOPE.md](docs/SEPTEMBER_SCOPE.md)。

## 项目结构

```text
hooklab/core       领域模型与稳定错误码
hooklab/crypto     SHA-256 / HMAC-SHA256
hooklab/providers  提供方验签适配器
hooklab/engine     幂等、路由、脱敏、重试、fixture
hooklab/event      接收事件模型与查询存储
hooklab/delivery   投递状态机、队列、重试和死信恢复
hooklab/contract   Webhook 契约验证
hooklab/config     版本化网关配置解析与全量校验
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
moon test --target all
moon build --target all --deny-warn
node scripts/gateway-e2e.mjs
node scripts/gateway-config-e2e.mjs
node scripts/gateway-deadletter-e2e.mjs
node scripts/gateway-restart-e2e.mjs
```

项目采用 MIT 许可。
