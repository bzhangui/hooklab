# 运维与恢复边界

HookLab 的 Mooncakes 模块版本以 `moon.mod` 和公开注册表为准；完整平台仍只适合受控试用，不是公网生产认证。以下操作在[本机试用部署](DEPLOYMENT.md)之外，帮助操作者核查备份与恢复；任何真实事件正文、数据库归档、`.env` 和端点密钥都不得上传公开仓库或 CI artifact。

## 首次接入与常见失败

先运行 `npm run doctor` 区分“Docker 引擎未启动”“Compose 不可用”“本机服务未响应”。再按[首个事件指南](FIRST_EVENT.md)用本机发布令牌发送合成订单事件，回到门户刷新、查看事件轨迹。管理 Owner 令牌和应用发布令牌不能混用。

| 现象 | 优先检查 | 安全处理 |
| --- | --- | --- |
| 浏览器 `ERR_CONNECTION_REFUSED` 或 doctor 报本机服务未响应 | Docker Desktop、`docker compose ps`、`.env` 中端口、`docker compose logs app` | 不要为了访问而把绑定地址直接改成公网 |
| 发布返回 401 | 应用发布令牌、租户/应用 ID、应用是否启用 | 重新创建/轮换令牌；不要把令牌粘贴到工单 |
| 返回 422 或 409 | 正文 JSON、事件契约、幂等键与原正文是否一致 | 修正新请求；不要用原幂等键发送不同正文 |
| 接受事件但交付数为 0 | 订阅的应用、事件类型、启用状态及端点 | 改正订阅后发送**新事件**；已接收事件不会自动补建交付 |
| 端点创建返回 `target_not_allowed` | `HOOKLAB_OUTBOUND_HOST_ALLOWLIST` 是否含端点的精确主机名 | 由操作者核对授权域名；不要用通配符绕过 |
| 死信或持续重试 | 门户轨迹里的最近错误、HTTP 状态、接收方验签/去重、端点可用性 | 修复接收方后重试死信；可能重复投递，先确保业务去重 |
| 数据库恢复后旧交付无法签名 | 恢复时的 `HOOKLAB_ENCRYPTION_KEY` 是否与归档清单的指纹匹配 | 停止切换流量；从独立加密备份找回原密钥，不要重建新密钥覆盖 |

排查日志和工单只记录事件/交付 ID、错误码、时间和脱敏状态；原始正文、数据库归档、令牌及密钥不可公开。门户只展示最近 100 条记录，缺失不等于数据库无记录。

## 每次备份的核验

1. 在服务正常运行、磁盘空间足够时执行 `npm run backup:verify`。脚本把 PostgreSQL 自定义格式归档恢复到随机命名的**独立临时数据库**，验证 schema v3 的 13 张预期表、租户/事件/端点/提供方凭据/尝试计数；如有端点或提供方凭据，还用当前加密密钥解密一条恢复后的对应密钥。原数据库不被覆盖。
2. 成功后，`backups/` 内会有 `.dump` 与同名 `.dump.manifest.json`。清单记录归档 SHA-256、密钥指纹、schema 版本和恢复计数，不包含密钥正文；清单与归档都按敏感材料保管。
3. 把归档、清单和**单独加密保管**的 `.env` 移至操作者控制的异地存储。不要把三者一起明文放在共享目录。复制到另一台机器后，运行 `npm run backup:inspect -- <归档路径>` 核对归档校验和与密钥指纹。此检查不连接数据库，不能代替第 1 步的恢复演练。

CI 在一次性 PostgreSQL 中执行完整投递闭环和临时库恢复，还会从同一归档启动**另一个全新 Compose 卷**上的应用并核对合成事件。它不是跨主机或真实生产灾备演练。真实部署仍应定期在**新主机/新卷**执行完整启动演练，并记录演练日期、版本、归档校验和与结果。本仓库不自动传送备份到异地，也不替用户选择存储服务或密钥托管方。

## 恢复到新环境的人工流程

只在独立环境操作，不对现有生产库执行 `pg_restore`，不删除原卷：

1. 使用与归档兼容的仓库版本和 PostgreSQL 版本，在受控环境准备一份私有 `.env`。先检查 `HOOKLAB_ENCRYPTION_KEY` 与备份清单匹配；不要用 `quickstart` 生成的新密钥替代旧密钥。
2. 为演练选择全新的 Compose 项目名和空卷。只启动 `database`，确认目标库无 HookLab 表，再将 `.dump` 复制到数据库容器并用 `pg_restore --exit-on-error --no-owner --no-acl` 恢复。目标非空或来源不明时应停止，不要尝试覆盖。
3. 启动同版本 `app`，检查 `/health`、一个经授权的租户只读查询，以及一条由受控接收端验证签名的合成事件。完成后核对恢复计数、数据保留边界和告警，再决定是否切换流量。
4. 预留旧部署和归档作为回滚点。发现 schema 不兼容、密钥不匹配、出站请求异常或记录缺失时，不切换流量。

例如，在已经核对过归档、且确认 `hooklab_recovery_trial` 项目名从未使用过的独立机器上，可按以下顺序操作（将占位文件名换成自己的归档；命令不应用于现有数据库）：

```bash
npm run backup:inspect -- backups/your-backup.dump
docker compose -p hooklab_recovery_trial up -d database
docker compose -p hooklab_recovery_trial cp backups/your-backup.dump database:/tmp/hooklab-recovery.dump
docker compose -p hooklab_recovery_trial exec -T database pg_restore -U hooklab -d hooklab --exit-on-error --no-owner --no-acl /tmp/hooklab-recovery.dump
docker compose -p hooklab_recovery_trial up --build -d app
docker compose -p hooklab_recovery_trial ps
```

不要在 `pg_restore` 失败后继续启动应用；也不要用 `docker compose down --volumes` 清理任何有价值的数据。受控演练结束后的归档、容器与卷清理由操作者在确认目标身份和备份后执行。

`backup:verify` 只执行第 2 步的隔离数据库恢复核验；CI 另外在全新卷上执行一次合成应用启动。两者都没有实现跨主机切换或高可用。现有 PostgreSQL v1/v2→v3 加法迁移必须先做备份并明确启用；保留期删除须先预览且仅按租户逐批执行，具体见[升级与保留操作](RETENTION.md)。任意版本在线升级、自动备份轮换和运行中 SQLite→PostgreSQL 队列迁移尚未提供；仅支持[已结束事件历史转移](MIGRATION.md)。不要把本说明误读为已经进行生产故障恢复演练。

## 当前生产拦截项

- 公网入口需要受控 TLS 反向代理、网络出站 ACL 和独立身份系统；本机 Compose 仅绑定宿主机回环。数据库试用账户不是最小权限布局。
- PostgreSQL 模式可设置共享的每租户最近一小时已接受事件/正文总字节额度及待处理交付额度，并由双实例 CI 测试；默认关闭。它不限制管理请求、连接数或瞬时请求率，也不替代网络层限流。已有显式确认的租户级终态事件清理和 v1/v2→v3 加法迁移，但没有自动备份轮换、备份删除策略、数据库级 RLS 或任意版本在线升级；不能因 CI 通过而假定多租户生产隔离与容量已经验证。
- 出站语义为 **at least once**。消费者要验证 HMAC、检查时间戳并按投递 ID 去重；`interrupted` 表示结果未知，不表示消息必然送达或未送达。
