# SQLite 已结束事件的受控历史转移

本工具解决**历史事件可携带、可预演**的问题，不是把运行中的 `serve-config` 无缝切换为 `serve-platform`。它保留事件的原始 JSON 正文、类型、提供方和接收时间；不导入旧投递队列、投递尝试、订阅、端点、密钥或路由配置。旧交付状态的计数保存在私有归档中供核对，平台内导入的历史事件没有可重试交付。不要把此工具描述成生产零停机迁移。

## 适用条件与边界

1. 停止旧 SQLite 网关写入，确认所有交付已是 `delivered`、`dead_lettered` 或 `cancelled`。工具发现待处理、重试中或租约中的交付会直接拒绝导出。若有死信，先由负责人决定继续保留旧网关、人工重试或明确放弃；本工具不会偷偷重投。
2. 分别备份并验证原 SQLite 数据库（连同 WAL）与目标 PostgreSQL 数据库。目标必须已经运行 schema v3，并已创建对应租户和应用；应用应只用于接收这批历史数据，避免混淆新事件。
3. 归档包含**原始事件正文**，应视同数据库备份。文件扩展名 `.hooklab-transfer.json` 已被 Git 忽略；仍须存放在访问受限、可加密的私有目录，不要作为工单附件或公开仓库文件。校验和用于发现意外改动，不是防止恶意篡改的认证签名。

## 导出、预演、执行

在仓库根目录、Node.js 24+ 环境下运行。路径和租户/应用 ID 请替换为自己的受控测试数据；**先预演，核对计数和目标**：

```bash
node scripts/sqlite-transfer.mjs export --sqlite .hooklab-data/hooklab.sqlite --out history.hooklab-transfer.json
DATABASE_URL='postgresql://...' node scripts/sqlite-transfer.mjs import --file history.hooklab-transfer.json --tenant acme --app incoming
```

只有确认目标、备份和预演无误后才执行：

```bash
DATABASE_URL='postgresql://...' node scripts/sqlite-transfer.mjs import --file history.hooklab-transfer.json --tenant acme --app incoming --apply --confirm-tenant acme --confirm-app incoming
```

Windows PowerShell 先分别设置 `$env:DATABASE_URL`，然后执行相同的 `node` 命令。执行时单个 PostgreSQL 事务写入；重新导入同一归档不会复制相同历史事件，正文或来源冲突会回滚。最多 10,000 个事件和 100 MiB 归档；更大数据集需要分批、流式方案，不能绕过上限直接用于生产。预演不会改动目标数据库。命令结果只打印计数和文件路径，不打印正文。

## 切换后核对

核对导出数、预演 `newEvents`、执行后的 `newEvents` 与平台事件列表；用新提供方地址、密钥、订阅和接收方做**全新合成事件**的签名与投递测试。旧系统的在途事件不能通过该工具自动继续：必须保持旧网关可恢复，或制定逐个事件的人工处理方案。切换失败时回到原系统或隔离备份环境，不要覆盖现用 PostgreSQL 库。
