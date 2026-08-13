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
delivery-id check-and-record ─重复──▶ acknowledge, no side effects
    │
    ├──▶ JSON route matching
    ├──▶ redacted diagnosis/report
    └──▶ delivery decision ──▶ retry / success / dead letter
```

顺序属于安全属性：只有验签成功的数据才能污染幂等表；只有首次出现的 delivery ID 才能触发副作用；脱敏副本用于诊断，已验签原文只留在当前交付路径。

## 包边界

- `core` 不依赖协议实现，定义稳定领域类型和机器错误码。
- `crypto` 是可移植的 SHA-256 / HMAC-SHA256 实现。
- `providers` 负责头格式、签名输入与时间戳规则，不承载业务副作用。
- `engine` 提供纯规则或小状态组件，可以单独测试。
- `pipeline` 固化正确的安全顺序。
- `report` 只接收处理结果，不能访问密钥。
- `cmd/hooklab` 是薄适配层，文件与网络 I/O 仅存在于 JS CLI。

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
