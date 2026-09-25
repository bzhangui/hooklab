# PostgreSQL 多租户事件交付平台

`serve-platform` 是与现有 `serve-config` 并行的部署模式，不读取或迁移 SQLite 数据。它把租户、应用、订阅、事件、交付、租约、审计和告警放在共享 PostgreSQL 中；MoonBit 负责订阅投递计划、出站签名和重试决策，Node.js 适配器负责 HTTP、数据库事务和网络传输。交付语义为 **at least once**，不是 exactly once。

## 快速启动

评审或本机试用可以先使用 [Docker Compose 一键启动与备份恢复](DEPLOYMENT.md)。以下命令适合已有独立 PostgreSQL 的手动部署；Compose 试用环境不等于公网生产部署。

环境：Node.js 24+、MoonBit CLI、PostgreSQL 17（CI 验证版本；其他版本尚未验证）。从仓库根目录执行：

```bash
npm ci
export DATABASE_URL='postgresql://hooklab:YOUR_PASSWORD@127.0.0.1:5432/hooklab'
export HOOKLAB_ENCRYPTION_KEY='<32-byte-key-as-64-hex-characters>'
export HOOKLAB_BOOTSTRAP_TOKEN='<random-secret-at-least-32-characters>'
export HOOKLAB_METRICS_TOKEN='<different-random-secret-at-least-32-characters>'
moon run --target js cmd/hooklab -- serve-platform 8787
```

上述值是占位符，不能用于正式环境。首次启动自动建立 schema v1；启动时用 PostgreSQL advisory lock 串行化建表。数据库只应由 HookLab 使用。后续升级若引入更高版本 schema，旧程序会拒绝启动；当前没有 SQLite → PostgreSQL 自动迁移工具。`GET /health` 检查进程和数据库连接。门户位于 `http://127.0.0.1:8787/`，默认只监听回环地址。

## 从租户到交付

先用引导令牌创建租户，响应中的 `ownerToken` 只返回一次。以下命令用环境变量表示令牌；不要把真实值写入脚本或提交记录。

```bash
curl -X POST http://127.0.0.1:8787/api/admin/tenants \
  -H "Authorization: Bearer $HOOKLAB_BOOTSTRAP_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"id":"acme","name":"Acme"}'
```

将响应的 `ownerToken` 安全保存为 `OWNER_TOKEN`。创建应用和消费者端点，分别取得一次性 `publishToken` 和 `signingSecret`：

```bash
curl -X POST http://127.0.0.1:8787/api/tenants/acme/applications \
  -H "Authorization: Bearer $OWNER_TOKEN" -H 'Content-Type: application/json' \
  --data '{"id":"orders"}'
curl -X POST http://127.0.0.1:8787/api/tenants/acme/endpoints \
  -H "Authorization: Bearer $OWNER_TOKEN" -H 'Content-Type: application/json' \
  --data '{"id":"warehouse","url":"https://consumer.example.com/webhooks"}'
curl -X POST http://127.0.0.1:8787/api/tenants/acme/subscriptions \
  -H "Authorization: Bearer $OWNER_TOKEN" -H 'Content-Type: application/json' \
  --data '{"id":"orders-to-warehouse","applicationId":"orders","endpointId":"warehouse","eventTypes":["order.created"]}'
```

发布事件时用应用自己的令牌和幂等键。相同键、相同正文返回 200 `duplicate=true`，相同键但不同类型或正文返回 409。事件和所有交付在同一事务中写入。建议先发布事件契约，见下节。

```bash
curl -X POST http://127.0.0.1:8787/api/tenants/acme/applications/orders/events/order.created \
  -H "Authorization: Bearer $PUBLISH_TOKEN" -H 'Idempotency-Key: order-42-created' \
  -H 'Content-Type: application/json' --data '{"orderId":42}'
```

消费者收到原始 JSON 正文、`X-HookLab-Event-Id`、`X-HookLab-Delivery-Id`、`X-HookLab-Event-Type`、`X-HookLab-Key-Id`、`X-HookLab-Timestamp`、`X-HookLab-Signature` 和 `traceparent`。签名规范与 [OUTBOUND.md](OUTBOUND.md) 相同。重试会改变时间戳但保留事件/交付 ID。消费者应以交付 ID 去重。3xx 不跟随跳转；网络错误、408/425/429/5xx 按 MoonBit 重试策略处理，其他 4xx 进入死信。

Worker 领取任务时先在同一数据库事务中记录 `in_flight` 尝试，完成后更新为 `delivered`、`scheduled` 或 `dead_lettered`。如果 Worker 崩溃并由另一个实例接管，旧记录标为 `interrupted`，新尝试另起一条。`interrupted` 只表示原 Worker 未留下终态，**不能证明请求一定已到达消费者**；也不能据此保证恰好一次交付。未结束与中断的尝试不计入耗时 p95/直方图，但中断数量出现在尝试结果指标和租户历史中。

## 契约与 CloudEvents

按应用和事件类型发布递增版本的契约。每次发布只激活最新版本；MoonBit 领域内核判定版本兼容性，试图新增必填字段、收窄类型/枚举或关闭原本允许的额外字段会返回 409。契约变更在应用行锁下串行化。`GET /api/tenants/:tenant/contracts` 可查看版本与 schema。

```bash
curl -X POST http://127.0.0.1:8787/api/tenants/acme/contracts \
  -H "Authorization: Bearer $OWNER_TOKEN" -H 'Content-Type: application/json' \
  --data '{"applicationId":"orders","eventType":"order.created","version":1,"requireCloudEvents":true,"schema":{"type":"object","required":["orderId"],"properties":{"orderId":{"type":"integer"}}}}'
```

支持 UTF-8 JSON 的 CloudEvents 1.0 structured mode：`Content-Type: application/cloudevents+json`，且 `specversion`、`id`、`source`、`type` 必须存在；URL 事件类型须与 envelope 的 `type` 相同。契约验证作用于 `data`。当前不支持 `data_base64`、binary mode、batch、任意 JSON Schema 关键字。支持的 schema 关键字只有 `type`、`required`、`properties`、`items`、`enum`、`additionalProperties`；不支持的关键字在保存契约时拒绝，避免静默忽略。正文或契约无效返回 422，且不产生事件、幂等记录或交付。单次正文上限 1 MiB。

## 角色、密钥与门户

租户管理令牌拥有 `owner`、`developer`、`viewer` 三种角色。Owner 可发放/撤销其他管理令牌；Developer 可维护应用、端点、订阅和契约并重试死信；Viewer 只能查看目录、历史、SLO、告警和审计。所有查询按租户 ID 和令牌哈希过滤，不回显原始事件正文、发布令牌、签名密钥或加密后的密钥。

| 操作 | API |
|---|---|
| 发放 / 撤销管理令牌 | `POST /api/tenants/:id/keys`、`POST /api/tenants/:id/keys/:key/revoke` |
| 轮换应用令牌 | `POST /api/tenants/:id/applications/:app/rotate-token` |
| 轮换端点密钥 | `POST /api/tenants/:id/endpoints/:endpoint/rotate-secret` |
| 软停用 / 启用资源 | `PATCH /api/tenants/:id/applications|endpoints|subscriptions/:resource`，正文 `{"enabled":false}` |
| 目录与契约 | `GET /api/tenants/:id/catalog`、`GET /api/tenants/:id/contracts` |
| 事件、交付、尝试与审计 | `GET /api/tenants/:id/events|deliveries|audit`、`GET /api/tenants/:id/deliveries/:delivery/attempts` |
| 死信人工重试 | `POST /api/tenants/:id/deliveries/:delivery/retry` |

轮换后的新密钥只在响应中显示一次。已入队交付持有加密的旧密钥快照；消费者需要在过渡期继续接受旧 `keyId`，直到旧交付完成。门户令牌只在当前页面内存中，刷新或断开后清除；在可信设备上使用。

## 多实例、安全与运行边界

- 多个实例可连接同一 PostgreSQL。Worker 用 `FOR UPDATE SKIP LOCKED` 领取任务，续租并用 `worker_id` + `lease_token` 条件写回，租约过期可接管。网络发送已发生但写回失败时仍可能重复，无法保证 exactly once。
- 管理、发布、指标令牌各自独立。发布令牌随机生成并仅存 SHA-256 摘要；端点签名密钥以 `HOOKLAB_ENCRYPTION_KEY` 用 AES-256-GCM 加密。备份数据库时也必须安全备份该密钥，丢失后旧交付无法签名。请为数据库连接配置 TLS、最小权限账户与可靠备份。
- 端点只允许 HTTPS（测试时设置 `HOOKLAB_ALLOW_LOOPBACK_ENDPOINTS=1` 才允许回环 HTTP）。禁止 URL 用户名、密码、查询参数和片段；创建及每次发送都解析 DNS，拒绝私网/回环/链路本地等地址，并把连接固定到检查过的 IP。禁止重定向。此策略降低 SSRF 风险，但仍需网络出口 ACL、DNS/代理审计和允许的目标清单。
- 默认回环绑定。跨主机服务必须通过受信任的 TLS 反向代理和防火墙发布，绝不可把纯 HTTP 的管理接口直接暴露公网。平台当前没有全局租户配额、跨实例限流、自动 TLS、外部身份提供方、数据库级 RLS、在线扩缩容迁移或消费者自助证明域名所有权。
- 当前 PostgreSQL 模式仅服务应用事件发布；原有第三方入站 Webhook 验签仍用 `serve-config`。两条运行路径不会自动共享事件或迁移数据。

## 观测、SLO、告警与维护测试

`GET /metrics` 用独立的 `HOOKLAB_METRICS_TOKEN` 访问，输出无租户/URL 标签的 Prometheus 指标：状态数、24 小时尝试结果、尝试耗时固定桶、最老积压秒数、打开的告警数及本实例活动 Worker 数。`GET /api/tenants/:id/slo` 输出 24 小时投递成功率和 p95 尝试耗时。成功率分母包括窗口内创建、仍在排队的交付；无样本返回 `null`。内置告警检查最近一小时死信及超过五分钟的积压，结果见租户告警 API。生产通知可用 [Prometheus 告警规则示例](../ops/prometheus-rules.yml) 接入 Alertmanager；HookLab 自身不发送邮件或短信。

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --deny-warn
npm ci
npm run test:platform
# 使用专用 hooklab_test 数据库运行真正的多实例测试：
TEST_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/hooklab_test' node scripts/platform-e2e.mjs
TEST_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/hooklab_test' node scripts/platform-showcase.mjs
```

`platform/schema.test.cjs` 使用 PGlite 检查表结构和租户外键；它不能替代真实 PostgreSQL 的并发语义。CI 的 PostgreSQL 17 服务执行双实例端到端测试。升级前备份数据库并在相同版本的测试环境演练恢复；监控 CI、死信、积压、SLO 和密钥轮换记录。

第二个脚本会强制终止它自己启动的一个 Worker，以验证租约到期后的接管；同时输出仅针对本机合成负载的耗时样本。运行前请阅读[季度评选证据与边界](QUARTERLY_EVIDENCE.md)，不要将样本当成生产性能或真实用户成效。
