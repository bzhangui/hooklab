# 提供方协议

HookLab 对签名使用十六进制小写输出，比较前验证长度和字符格式，再进行常量时间比较。HTTP 头查询不区分 ASCII 大小写。

## GitHub

- Header：`X-Hub-Signature-256: sha256=<hex>`
- 输入：未经修改的原始请求体
- 算法：`HMAC-SHA256(webhook_secret, raw_body)`
- 事件/ID：`X-GitHub-Event`、`X-GitHub-Delivery`

GitHub 协议本身没有签名时间戳，因此依赖 delivery ID 幂等防止同一进程窗口内重复副作用。

## Stripe

- Header：`Stripe-Signature: t=<unix_seconds>,v1=<hex>[,v1=<rotated_hex>]`
- 输入：`timestamp + "." + raw_body`
- 算法：HMAC-SHA256
- 默认容差：300 秒；支持多个 `v1`，便于密钥滚动期间验证。

Stripe 事件 ID 位于 JSON payload。为保持验签层只处理原始输入，当前 CLI/通用接口接受代理层提供的 `X-HookLab-Delivery-Id`。生产适配器应在验签成功后解析 payload 的 `id` 并原子写入幂等存储。

## 飞书 / Lark

- Headers：`X-Lark-Request-Timestamp`、`X-Lark-Request-Nonce`、`X-Lark-Signature`
- 输入：`timestamp + nonce + encrypt_key + raw_body`
- 算法：SHA-256
- nonce 同时作为当前实现的 delivery ID。

这里的 secret 参数对应事件订阅配置中的 Encrypt Key，而不是 Verification Token。

## 通用 HMAC

- Headers：`X-Webhook-Signature`、可选 `X-Webhook-Timestamp`、`X-Webhook-Id`
- 输入：存在时间戳时为 `timestamp + "." + raw_body`，否则为原始请求体
- 算法：HMAC-SHA256

通用协议只是一套明确约定，并不自动兼容所有厂商。若厂商将时间戳、路径或方法拼入签名，应新增专用适配器，不要强行套用。

## 时间与密钥

默认接受过去 300 秒内的事件，允许最多 30 秒未来偏差。测试中可以显式传入策略，生产中不建议无上限扩大容差。密钥应来自密钥管理服务或环境注入，不应出现在仓库、命令历史、fixture 或报告中；CLI 的明文参数只适合本地演示。
