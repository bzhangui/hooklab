# HookLab

[Mooncakes 上的 HookLab 模块](https://mooncakes.io/docs/bzhangui/hooklab)已公开发布；源码版本见 `moon.mod`，可用 `moon view bzhangui/hooklab --versions` 核对已发布版本。这是可安装的 MoonBit 核心库，不代表完整平台已公开托管或达到生产就绪。

[![CI](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml/badge.svg)](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-JS%20%7C%20Wasm%20%7C%20Native-blue)](https://www.moonbitlang.com/)

验收要求 `moonc >= 0.10.14`。运行 `moon version --all` 和 `node scripts/check-moonc-version.mjs` 可核对本机版本；CI 也强制执行同一版本门槛。第一次复核建议从[评审快速上手](docs/REVIEWER_QUICKSTART.md)开始；九项验收材料、发布记录与独立安装验证见[验收清单](docs/ACCEPTANCE.md)。

HookLab 是一个以 MoonBit 领域内核为基础的自托管 Webhook 安全与事件交付平台。它把最容易出事故的环节——**原始负载验签、时间窗校验、防重放、事务持久化、路由、受限转换、应用事件发布、出站签名、Worker 租约、可靠重试、死信与回放**——放进一条可测试、可运行的处理流水线。现有 SQLite 单机模式之外，项目新增 PostgreSQL 多租户应用事件交付模式。

想先了解产品，可以打开[公开六场景交互演示](https://bzhangui.github.io/hooklab/)（[页面源码](docs/index.html)）：它只播放固定合成数据、不连接后端，不能代替真实试点。需要真正运行，请按[评审快速上手](docs/REVIEWER_QUICKSTART.md)在本机部署并执行[多角色合成试点](docs/SIMULATED_PILOT.md)。[模式选择与兼容策略](docs/PRODUCT_PATH.md)解释新项目为何优先采用 PostgreSQL 平台，以及 SQLite 历史转移的边界。

它既适合比赛演示，也解决真实工程问题：第三方回调“为什么验签失败”、同一事件“为什么执行两次”、失败请求“如何安全复现”、下游暂时不可用“如何可靠重试”。MoonBit 领域代码可以编译到 JS、Wasm、Wasm-GC 和 Native；服务器适配器运行在 Node.js。

## 从 Mooncakes 使用 MoonBit 核心库

在一个新的 MoonBit 项目中运行 `moon add bzhangui/hooklab`，或从注册表选定版本后显式固定 `@版本号`。例如，在可执行包的 `moon.pkg` 中引入 `"bzhangui/hooklab/hooklab/crypto" @crypto`，再调用 `@crypto.sha256_hex("abc")`，运行结果应为 `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`。可用 `node scripts/mooncakes-smoke.mjs` 在隔离的新项目中自动复核注册表最新版本，也可在命令末尾传入具体版本号。完整的自托管事件交付服务仍按下文从仓库源码部署，不能只靠 `moon add` 启动。

## 两种运行模式

| 模式 | 适用情况 | 存储与边界 |
|---|---|---|
| `serve-config` | 第三方 Webhook 验签、路由和单机交付 | 本机 SQLite，静态受信任配置；现有示例可直接运行 |
| `serve-platform` | 应用事件发布、第三方 Webhook 验签接入、消费者管理和多实例交付 | 共享 PostgreSQL，多租户令牌/角色、契约、CloudEvents、SLO 与告警 |

两种模式仍独立部署；`serve-platform` 现在可在同一 PostgreSQL 事件链路接入第三方提供方，但不会自动接管旧 SQLite 数据。受控的已结束历史事件导出/导入见[转移说明](docs/MIGRATION.md)，不迁移活动队列和密钥。运行命令、API、安全边界见[平台使用说明](docs/PLATFORM.md)，核心接口另有[机器可读描述](docs/openapi.json)。

PostgreSQL 模式可选共享数据库的每租户小时事件、小时正文总字节、待处理交付额度；默认关闭。另有可选的单进程 HTTP 在途请求保险丝 `HOOKLAB_MAX_INFLIGHT_REQUESTS`。这些都不等于跨实例通用请求/连接限流，公网前仍需可信 TLS 代理和网络边界，见 [SECURITY.md](SECURITY.md) 与[公网部署拦截项](docs/PRODUCTION_BOUNDARY.md)。

## 本机一键试用与备份验证

安装 Docker Compose v2 和 Node.js 24+ 后，在仓库根目录运行 `npm run quickstart`：脚本生成 Git 忽略的私有 `.env`，构建应用并启动 PostgreSQL 与 HookLab，默认只开放 `http://127.0.0.1:8787/`。运行 `npm run backup:verify` 会把数据库备份恢复到隔离的临时数据库，检查数据结构和已存端点密钥；归档与私有校验清单保存在 `backups/`。复制备份后可用 `npm run backup:inspect -- <归档路径>` 离线核对归档与加密密钥。密钥须单独安全保管。完整边界见[部署说明](docs/DEPLOYMENT.md)和[恢复运行手册](docs/OPERATIONS.md)；真实用户试用尚未开展，需先按[授权试用清单](docs/PILOT.md)准备。

PostgreSQL 模式的消费者门户现提供响应式工作台：交付健康度、告警、可搜索的事件/交付记录、事件轨迹、接入资源和操作入口。三步接入引导显示应用、端点、订阅的现有数量，示例按钮只填入参数，不会自动提交。它是随本地服务提供的管理页面，**不是公开部署的网站**；访问前应按[平台使用说明](docs/PLATFORM.md)准备租户令牌，并仅在可信地址输入。令牌不写入浏览器存储。

首次本机体验可在 `npm run quickstart` 成功后运行 `npm run local:workspace`。这会创建一个本机租户，把只显示一次的 Owner 令牌保存到被 Git 忽略的 `.env.portal-local`；在门户输入该文件中的租户 ID 和令牌即可连接。此文件是明文私有凭据，不要上传、截图分享或放入公共目录。重复运行只会验证已有凭据，不会覆盖。

## 季度评选：可复现的交付证据

在专用 PostgreSQL 测试库运行 `TEST_DATABASE_URL=... node scripts/platform-showcase.mjs`，可复现“订单事件 → 仓库消费者”场景：非法事件被拒绝且不入库、Worker 处理途中被强制终止、另一实例在租约到期后接管同一交付，以及 32 条合成事件的本机耗时样本。脚本验证结果并输出 JSON；[演示与证据说明](docs/QUARTERLY_EVIDENCE.md)列出前提、观察点和不能从样本推出的生产结论。CI 会在真实 PostgreSQL 17 服务上执行这一脚本。演示不代表已有真实用户或生产部署。

CI 另在独立容器中核对签名投递、503→204 重试、幂等和备份恢复；[MoonBit 核心职责](docs/MOONBIT_CORE.md)说明各层真实实现位置。

接收系统可使用[Node.js 验签模块和两个接收端示例](docs/RECEIVER.md)核对原始正文、时间窗和签名；其中 SQLite 示例把去重键与业务状态写入同一持久事务，并测试重启后的重复投递。模块尚未发布到 npm，示例只监听回环。PostgreSQL 模式另提供[受控 v1/v2→v3 升级与事件保留工具](docs/RETENTION.md)：升级旧库前要验证备份，清理默认只预览，执行时必须显式确认租户。

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
| 多租户控制面 | PostgreSQL 租户、应用、端点、订阅，Owner/Developer/Viewer 角色、审计、消费者门户和一次性密钥轮换 |
| 分布式交付 | PostgreSQL 事务入队、跨实例任务竞争领取、续租、fencing、持久化尝试审计与死信恢复；至少一次交付 |
| 第三方入站闭环 | MoonBit 验签 GitHub、Stripe、飞书和通用 HMAC，请求通过后才在 PostgreSQL 原子保存事件和订阅交付 |
| 事件契约 | 版本化 JSON Schema 子集、非破坏性变更检查、CloudEvents 1.0 structured JSON 接入 |
| 运行观测 | Prometheus 指标、脱敏事件时间线、24 小时 SLO、p95 尝试及最终交付耗时、死信与积压告警 |
| 数据转移 | SQLite 已结束历史事件的私有导出、预览与显式确认导入；不迁移活动队列或密钥 |
| CLI | sign、verify/inspect、report、route-test、contract-check、config-check、retry-plan、replay、serve、serve-config、serve-platform |

## 设计边界

- 必须对收到的**原始请求体**验签，不能先解析再序列化。
- 路由转换只在验签成功后执行，并在幂等记录和持久化前原子完成；它不执行脚本、模板或网络调用。
- 密钥不会写入 fixture、报告或日志；诊断结果只保存脱敏内容。
- 核心库提供确定性内存语义。`serve-config` 使用 SQLite WAL；`serve-platform` 使用共享 PostgreSQL，可以运行多个投递实例，但数据库本身的高可用由部署方保障。
- CLI 的 replay 是显式调试操作，不会绕过目标服务认证；它不会转发原始提供方签名，目标端应使用隔离的测试入口。
- `serve-config` 的投递领取与幂等由 SQLite 协调；其限流、可选熔断和耗时指标仅在单个进程内生效。`serve-platform` 的领取、幂等及可选租户事件/正文总字节/积压额度由 PostgreSQL 协调。
- SQLite 模式的出站端点仍是受信任的启动配置；PostgreSQL 模式允许租户管理端点，发送时重新解析并固定公共 IP、拒绝私网和重定向。网络出口 ACL 仍是必要的第二道防线。
- PostgreSQL 模式仍没有自动 TLS、通用请求/连接限流、数据库级 RLS 或完整资源配额；只能通过受信任的 TLS 代理和网络边界对外服务。交付是至少一次，消费者必须自行去重。
- 当前按 UTF-8 文本处理请求体。任意二进制负载应在接入层保留原始字节后扩展 `WebhookRequest`。

运行网关见 [docs/GATEWAY.md](docs/GATEWAY.md)，PostgreSQL 平台见 [docs/PLATFORM.md](docs/PLATFORM.md)，出站发布与验签见 [docs/OUTBOUND.md](docs/OUTBOUND.md)，声明式配置见 [docs/CONFIGURATION.md](docs/CONFIGURATION.md)，规则化转换见 [docs/TRANSFORMS.md](docs/TRANSFORMS.md)，契约验证见 [docs/CONTRACTS.md](docs/CONTRACTS.md)，架构与扩展点见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，提供方协议见 [docs/PROVIDERS.md](docs/PROVIDERS.md)，威胁模型见 [SECURITY.md](SECURITY.md)，性能基线见 [BENCHMARK.md](BENCHMARK.md)，后续路线见 [docs/ROADMAP.md](docs/ROADMAP.md)，九月新增范围见 [docs/SEPTEMBER_SCOPE.md](docs/SEPTEMBER_SCOPE.md)。

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
platform           PostgreSQL 多租户 HTTP/Worker 适配器、门户与结构测试
ops                Prometheus 告警规则示例
examples           可复现实例
```

## 验证

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --deny-warn
node scripts/check-core-coverage.mjs
node scripts/check-moonc-version.mjs
node scripts/check-package-contents.mjs
node scripts/gateway-e2e.mjs
node scripts/gateway-config-e2e.mjs
node scripts/gateway-limits-e2e.mjs
node scripts/gateway-circuit-e2e.mjs
node scripts/gateway-deadletter-e2e.mjs
node scripts/gateway-restart-e2e.mjs
node scripts/gateway-outbound-e2e.mjs
node scripts/gateway-lease-e2e.mjs
npm ci
npm run test:platform
# 使用专用 PostgreSQL 测试库设置 TEST_DATABASE_URL 后：
node scripts/platform-e2e.mjs
node scripts/platform-showcase.mjs
```

项目采用 MIT 许可。
