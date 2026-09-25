# 运维与恢复边界

HookLab `0.3.0-rc.2` 仍是受控试用候选版，不是公网生产认证。以下操作在[本机试用部署](DEPLOYMENT.md)之外，帮助操作者核查备份与恢复；任何真实事件正文、数据库归档、`.env` 和端点密钥都不得上传公开仓库或 CI artifact。

## 每次备份的核验

1. 在服务正常运行、磁盘空间足够时执行 `npm run backup:verify`。脚本把 PostgreSQL 自定义格式归档恢复到随机命名的**独立临时数据库**，验证 12 张预期表、租户/事件/端点/尝试计数；如有端点，还用当前加密密钥解密一条恢复后的端点密钥。原数据库不被覆盖。
2. 成功后，`backups/` 内会有 `.dump` 与同名 `.dump.manifest.json`。清单记录归档 SHA-256、密钥指纹、schema 版本和恢复计数，不包含密钥正文；清单与归档都按敏感材料保管。
3. 把归档、清单和**单独加密保管**的 `.env` 移至操作者控制的异地存储。不要把三者一起明文放在共享目录。复制到另一台机器后，运行 `npm run backup:inspect -- <归档路径>` 核对归档校验和与密钥指纹。此检查不连接数据库，不能代替第 1 步的恢复演练。

CI 在一次性 PostgreSQL 中执行完整投递闭环和临时库恢复。真实部署还应定期在**新主机/新卷**执行完整启动演练，并记录演练日期、版本、归档校验和与结果。本仓库不自动传送备份到异地，也不替用户选择存储服务或密钥托管方。

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

自动化脚本目前只完成第 2 步的隔离数据库恢复核验，并没有实现跨主机切换或高可用。使用中的数据库升级、自动备份轮换和 SQLite→PostgreSQL 迁移也尚未提供。不要把本说明误读为已经进行生产故障恢复演练。

## 当前生产拦截项

- 公网入口需要受控 TLS 反向代理、网络出站 ACL 和独立身份系统；本机 Compose 仅绑定宿主机回环。数据库试用账户不是最小权限布局。
- PostgreSQL 模式可设置共享的每租户最近一小时已接受事件额度，并由双实例 CI 测试；默认关闭。它不限制管理请求、正文总字节、连接数或已入队交付，也不替代网络层限流。数据库级 RLS、事件保留/删除策略和在线 schema 升级工具仍缺失；不能因 CI 通过而假定多租户生产隔离与容量已经验证。
- 出站语义为 **at least once**。消费者要验证 HMAC、检查时间戳并按投递 ID 去重；`interrupted` 表示结果未知，不表示消息必然送达或未送达。
