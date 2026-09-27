# PostgreSQL schema 升级与事件保留

以下仅适用于 `serve-platform`；SQLite `serve-config` 不会自动迁移到 PostgreSQL。PostgreSQL schema v2 是在 v1 上增加事件保留索引的**加法迁移**，不删除历史记录。首次初始化自动到 v2；已有 v1 库不会静默升级，必须先验证备份并显式启用一次升级。

1. 停止写入并安排维护窗口，按 [运维手册](OPERATIONS.md)执行 `npm run backup:verify`，安全保管归档、清单和独立加密的 `HOOKLAB_ENCRYPTION_KEY`。不要只检查归档存在；应完成隔离恢复。
2. 设置 `DATABASE_URL` 指向目标专用库，运行 `npm run schema:inspect`。输出 `upgrade_required` 且版本为 `[1]` 时才需升级；`unsupported` 时停止，不要尝试自动修复。
3. 仅在本次经过授权的启动中设置 `HOOKLAB_ALLOW_SCHEMA_UPGRADE=1`，启动新版本。Compose 部署可临时在私有 `.env` 加入这一行，完成后立即删除并重启；其他部署直接传给应用进程。平台持 PostgreSQL advisory lock，事务性执行 v2 迁移；失败会回滚迁移并拒绝启动。升级成功后移除该环境变量，再运行 `npm run schema:inspect`，应为 `current`、`[1,2]`，`/health` 的 `schemaVersion` 为 2。
4. 旧版本程序拒绝读取更高版本 schema；回滚应用前，须在隔离环境验证与升级前归档配套的恢复步骤，**不要**对现用库执行覆盖恢复。

迁移是低风险的索引增加，但创建索引可能阻塞写入，仍要选择维护窗口。启动时会核查版本历史和预期表/索引，不会在已标记的残缺数据库上自动补表。当前只覆盖 PostgreSQL v1→v2，不提供跨数据库或 SQLite 迁移。

## 保留期：先预览，再分批执行

默认命令**只预览**，不删除任何数据；最短 30 天，单批最多 500 个事件，作用域必须是一个明确租户。保留判断同时要求事件创建时间和所有相关交付的最后更新时间都早于截止时间，且所有交付已 `delivered` 或 `dead_lettered`。仍在排队、重试或租约中的事件不会删除。备份与 `audit_entries` 不随事件清理；因此审计中可能保留资源标识，须另行制定合规保存政策。

```bash
DATABASE_URL='postgresql://...' npm run retention -- --tenant acme --days 90 --limit 100
```

确认预览、备份和租户身份后，才在受控环境执行一批：

```bash
DATABASE_URL='postgresql://...' npm run retention -- --tenant acme --days 90 --limit 100 --apply --confirm-tenant acme
```

Windows PowerShell 先单独设置 `$env:DATABASE_URL`，再运行相同的 `npm run retention -- ...`。执行后只输出计数与截止时间，不输出正文或密钥；实际删除在单个事务内按尝试→交付→事件顺序进行并写入数量审计。并发状态变化会使该批回滚，下一次重新预览。需要多批时逐批核对结果，不提供无人值守自动删除。

本机 Compose 的数据库默认不向宿主机开放端口。应先 `docker compose build app`，确保数据库正在运行，再在专用应用网络中执行只读检查或保留操作；不需要把数据库映射到公网：

```bash
docker compose run --rm app node scripts/schema-inspect.mjs
docker compose run --rm app node scripts/retention.mjs --tenant acme --days 90 --limit 100
# 仅在前述备份、预览和租户确认完成后：
docker compose run --rm app node scripts/retention.mjs --tenant acme --days 90 --limit 100 --apply --confirm-tenant acme
```

**不可逆边界**：删除事件会释放原 `Idempotency-Key` 的唯一性；很久以后重复发布同一键可能被当作新事件。因此保存期必须长于发布方最大重试/审计窗口，并与消费者确认死信可重试期限。旧备份仍含正文，清理在线库不等于清理备份；备份轮换、异地删除和法律保留需要由部署方单独落实。不要对真实库做演示性清理。
