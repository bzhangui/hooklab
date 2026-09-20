# 架构与实现思路

## 为什么选择这个方向

优秀开源作品常见的共同点不是功能数量，而是：问题具体、核心技术有辨识度、演示闭环短、架构可扩展。HookLab 把 MoonBit 的优势放在一个能测量、能跨端、又有实际需求的位置：同一份安全核心既能在服务端运行，也能生成浏览器可用的诊断能力；纯 MoonBit 密码学与确定性状态机让结果容易测试和复现。

## 数据流

```text
raw request
    │
    ▼
provider signature ──失败──▶ stable error + remediation
    │
    ▼
timestamp freshness ─失败──▶ reject replay/stale event
    │
    ▼
JSON route matching + bounded transform ─失败──▶ 422, no side effects
    │
    ▼
delivery-id check-and-record ─重复──▶ acknowledge, no side effects
    │
    ▼
accepted event ──▶ atomic snapshot ──▶ redacted management view
    │
    ▼
delivery queue
    │
    ▼
per-target rate/concurrency + optional circuit gate
    │
    ├──2xx──────────────────────────▶ delivered
    ├──408/425/429/5xx/transport────▶ scheduled retry
    └──permanent/exhausted──────────▶ dead letter ──▶ manual recovery
```

顺序属于安全属性：只有验签成功的数据才能进入路由和转换；所有匹配路由的转换都必须在写入幂等记录前完成，因此超限或缺失路径不会留下部分状态；只有首次出现的 delivery ID 才能触发副作用。管理接口只使用脱敏副本，原始正文和按路由生成的正文仅保存在受保护的本地交付状态中。

## 包边界

- `core` 不依赖协议实现，定义稳定领域类型和机器错误码。
- `crypto` 是可移植的 SHA-256 / HMAC-SHA256 实现。
- `providers` 负责头格式、签名输入与时间戳规则，不承载业务副作用。
- `engine` 提供幂等、路由、脱敏和重试等纯规则或小状态组件。
- `event` 定义已接收事件以及可替换的查询存储语义。
- `delivery` 定义可持久化的投递生命周期、领取规则、死信恢复，以及按目标熔断与匿名耗时统计。
- `contract` 校验事件传输契约，并一次返回全部问题。
- `config` 解析版本化部署配置，拒绝明文密钥并聚合字段错误。
- `transform` 执行 set/remove/copy JSON 规则并强制输入、输出与操作数预算。
- `gateway` 固化验签、路由转换、幂等、持久化和任务创建的顺序。
- `pipeline` 保留轻量库使用场景的安全处理入口。
- `report` 只接收处理结果，不能访问密钥。
- `cmd/hooklab` 提供 JS/Node I/O 适配、本地持久化、管理 API 与控制台。

## 生产扩展

1. 用数据库唯一索引实现原子的 `(provider, delivery_id)` 插入，并给记录设置保留期。
2. 将 `RouteMatch.target` 映射到队列主题，不要把不受信任 payload 直接用作 URL。
3. 将重试步骤放进持久化任务队列；worker 按 `DeliveryDecision` 更新状态。
4. 记录摘要、状态码和 trace ID，不记录密钥、认证头或未脱敏 payload。
5. 为自定义提供方实现独立适配函数，并使用供应商官方测试向量验证。

## 验收标准

- 任意一字节 payload 改动都使签名失败。
- 过期或明显未来的带时间戳事件被拒绝。
- 同一个 delivery ID 在 TTL 内只被接受一次。
- 日志和报告不包含默认敏感字段值。
- 重试有上限，永久错误直接进入死信，不会无限循环。
- 所有支持目标无警告编译，测试在所有目标通过。
