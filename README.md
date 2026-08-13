# HookLab

[![CI](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml/badge.svg)](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-JS%20%7C%20Wasm%20%7C%20Native-blue)](https://www.moonbitlang.com/)

HookLab 是一个用 MoonBit 编写的跨平台 Webhook 安全与可靠性交付工具箱。它把最容易出事故的环节——**原始负载验签、时间窗校验、防重放、幂等、路由、敏感字段脱敏、重试与离线诊断**——放进一条可测试的处理流水线。

它既适合比赛演示，也解决真实工程问题：第三方回调“为什么验签失败”、同一事件“为什么执行两次”、失败请求“如何安全复现”、下游暂时不可用“如何重试而不制造重复副作用”。核心实现不依赖云服务，MoonBit 代码可以编译到 JS、Wasm、Wasm-GC 和 Native。

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
| 内容路由 | JSON 点路径的 equals / not-equals / exists / contains |
| 隐私保护 | 嵌套 JSON 字段和 HTTP 头大小写不敏感脱敏 |
| 可靠交付 | 确定性指数退避、状态分类、最大尝试次数、死信决策 |
| 可复现诊断 | 无密钥 replay fixture、机器可读 JSON、单文件离线 HTML |
| CLI | sign、verify/inspect、report、route-test、retry-plan、replay |

## 设计边界

- 必须对收到的**原始请求体**验签，不能先解析再序列化。
- 密钥不会写入 fixture、报告或日志；诊断结果只保存脱敏内容。
- 内存幂等存储适合单进程工具和演示。多实例生产环境应将相同的 `check-and-record` 语义落到具备唯一约束/事务的数据库。
- CLI 的 replay 是显式调试操作，不会绕过目标服务认证；它不会转发原始提供方签名，目标端应使用隔离的测试入口。
- 当前按 UTF-8 文本处理请求体。任意二进制负载应在接入层保留原始字节后扩展 `WebhookRequest`。

架构与扩展点见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，提供方协议见 [docs/PROVIDERS.md](docs/PROVIDERS.md)，威胁模型见 [SECURITY.md](SECURITY.md)。

## 项目结构

```text
hooklab/core       领域模型与稳定错误码
hooklab/crypto     SHA-256 / HMAC-SHA256
hooklab/providers  提供方验签适配器
hooklab/engine     幂等、路由、脱敏、重试、fixture
hooklab/pipeline   安全处理顺序
hooklab/report     JSON 与离线 HTML 诊断
cmd/hooklab        JS/Node CLI
examples           可复现实例
```

## 验证

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all
moon build --target all --deny-warn
```

项目采用 MIT 许可。
