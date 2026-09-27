# Node.js 接收方集成包（受控示例）

`sdk/node/receiver.cjs` 是可直接引用的零运行时依赖验签模块，不是已经发布到 npm 的包。它与 MoonBit 出站签名共享固定测试向量，CI 的 Compose 投递测试也用它核对真实收到的两次重试。平台向接收方提供 **at least once** 投递；验签成功不等于业务恰好执行一次。

现在还提供 `examples/receiver-durable/server.cjs`：在 Node.js 24+ 内置 SQLite 中把 `(consumer_id, delivery_id)` 唯一键与示例库存更新放在**同一事务**，并保存事件/正文指纹；进程重启后同一投递不会重复更新库存，同一投递 ID 配上不同正文返回 409。测试覆盖伪造签名、无效正文、重启去重和新事件。它是可改造的本机业务事务模式，仍不代表已获真实接收方授权或可直接公开部署。

## 本机跑通

`examples/gateway/outbound-config.json` 的示例端点是 `http://127.0.0.1:9090/events`。在第一个终端设置**同一个**本机演示密钥并运行接收端：

```powershell
$env:HOOKLAB_RECEIVER_SECRET = "endpoint-development-secret"
$env:HOOKLAB_RECEIVER_KEY_ID = "warehouse-v1"
node examples/receiver-node/server.cjs
```

第二个终端按 [出站服务指南](OUTBOUND.md) 设置 `HOOKLAB_SIGN_WAREHOUSE` 为同一密钥，并启动 `serve-config`，再使用该指南中的 `curl` 发布示例事件。接收端只监听回环地址，不记录正文或密钥；它的 `Set` 去重只用于本机演示，进程重启即丢失，达到 10,000 个 ID 后返回 503，**不能直接公开部署**。

试用持久示例时，将第一个终端的启动命令改为 `node examples/receiver-durable/server.cjs`，并可设置私有 `HOOKLAB_RECEIVER_DB` 路径；它只接受 `warehouse.updated`，正文须为 `{"itemId":"part-1","stock":7}` 这类 JSON。示例数据库及 WAL 文件不可提交。切换真实业务时，替换库存写入逻辑，但保留验签、唯一键、业务写入同一事务和失败返回非 2xx 的顺序。若业务状态在远程系统、无法和去重表同事务提交，应改用本地 outbox，再异步完成外部副作用，不能承诺恰好一次。

## 在自己的 HTTP 服务中使用

先在读取 JSON 之前保留 HTTP 原始字节。`headers` 传 Node.js 的 `request.headers`，`body` 传 `Buffer`，`secrets` 按公开的 `X-HookLab-Key-Id` 索引当前和过渡期旧密钥：

```js
const {verifyDelivery} = require('./sdk/node/receiver.cjs');
const result = verifyDelivery({headers: request.headers, body: rawBody,
  secrets: {[currentKeyId]: currentSecret, [oldKeyId]: oldSecret}});
if (!result.ok) return unauthorized();
```

默认时间窗为前后 300 秒；可显式传 `nowMs`、`toleranceSeconds`。返回 `invalid_headers`、`stale_timestamp`、`unknown_key` 或 `invalid_signature` 时都不要执行业务副作用；对外可以统一返回 401，避免暴露密钥状态。必须保持服务器时钟同步。签名规范和原始正文字节要求见 [OUTBOUND.md](OUTBOUND.md)。

验签后，接收方应在**同一持久事务**中插入 `(consumer_id, delivery_id)` 唯一键并完成业务变更：唯一键冲突表示重复投递，直接返回 2xx；事务失败返回非 2xx 供 HookLab 重试。不要先返回成功再异步处理，也不要用进程内 `Set` 承诺去重。HookLab 保留稳定的投递 ID，但每次重试的时间戳和签名可能不同。只有接收方掌握业务事务边界，本仓库无法替其保证恰好一次业务效果。

`npm run test:platform` 执行跨语言固定向量、篡改、过期、未知密钥和重复头等检查；CI 的隔离 Compose 测试还验证真实 MoonBit/Node.js 投递请求与该模块兼容。真实网络接入须取得端点所有者授权，使用受控 TLS 和持久去重存储。
