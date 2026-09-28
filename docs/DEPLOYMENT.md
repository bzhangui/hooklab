# 本机试用部署与备份恢复

本部署包用于个人试用、评审复现和受控试点。它不是公网生产部署方案：应用端口仅绑定宿主机 `127.0.0.1`，不提供 TLS 终止、跨实例通用请求/连接限流、数据库级 RLS 或外部身份系统。请先阅读 [PLATFORM.md](PLATFORM.md) 与 [SECURITY.md](../SECURITY.md)。

需要了解公网部署前仍缺什么，见[生产边界清单](PRODUCTION_BOUNDARY.md)。`HOOKLAB_MAX_INFLIGHT_REQUESTS` 可在私有 `.env` 中设置 1–99999 的单实例在途 HTTP 请求上限，超限返回 503 和 `Retry-After: 1`；默认 0 为关闭。它不是每秒速率限制，也不能代替可信 TLS 代理与多实例边缘限流。

## 一条命令启动

前提：Docker Engine 与 Docker Compose v2 正常工作，宿主机有 Node.js 24+ 和 npm；首次构建需要访问 Node 与 MoonBit 工具链下载源。在仓库根目录运行：

```bash
npm run quickstart
```

命令先检查 Docker Compose，再创建被 Git 忽略的私有 `.env`（已有文件不会覆盖），生成独立的数据库密码、AES-256-GCM 加密密钥、引导令牌和指标令牌，然后构建 MoonBit JS 程序、启动 PostgreSQL 17 与 HookLab，并等待 `/health`。默认地址为 `http://127.0.0.1:8787/`；端口占用时可在 `.env` 修改 `HOOKLAB_PORT` 后重跑。命令不打印密钥；需要引导令牌时在可信本机查看 `.env`。Windows 脚本会收紧私有文件及备份目录的 ACL，只允许当前用户、SYSTEM 和本机管理员访问；仍不要把它们放进共享目录或绕过操作系统账户保护。

Windows 用户可安装用户级 Docker Desktop 并先启动其 Linux 容器引擎；脚本会识别默认的用户级安装目录，不要求重新打开终端才能找到 Docker。服务就绪后运行 `npm run local:workspace`，脚本会创建一个本机租户，并把一次性 Owner 令牌写入 Git 忽略的 `.env.portal-local`；重复运行只验证已有令牌，不覆盖它。用文件中的租户 ID 和令牌在门户连接。该明文文件只适合可信的个人电脑，不要提交、发送或截图公开；丢失后无法从数据库回读原令牌。

若浏览器出现 `ERR_CONNECTION_REFUSED`，表示本机对应端口没有服务监听：先确认 Docker Desktop 已运行，再从仓库根目录执行 `npm run quickstart`，待其打印 `HookLab is ready` 后刷新页面。推送 GitHub 不会启动本机服务；`127.0.0.1` 在手机或其他电脑上指向那台设备自身，而不是运行 HookLab 的电脑。此试用部署只绑定本机回环地址，不应直接暴露公网。

容器使用非 root Node 用户运行应用；数据库卷由 Compose 管理。`docker compose down` 停止服务但保留卷，**不要**在有数据时使用 `down --volumes`。源码归档、容器镜像和 PostgreSQL 卷都不包含 `.env` 的备份副本；丢失 `HOOKLAB_ENCRYPTION_KEY` 会使旧投递的密钥快照无法解密，必须将它与数据库备份分开、加密并限制访问。数据库本身保存事件正文，备份也应视为敏感数据。

## 可恢复备份验证

在本机 Compose 服务正常运行后执行：

```bash
npm run backup:verify
```

脚本用 PostgreSQL 17 自带的 `pg_dump` 写入 Git 忽略的 `backups/` 目录，权限设为仅当前用户可读写；随后创建名称为 `hooklab_restore_` 加随机后缀的临时数据库，执行 `pg_restore`，检查 schema v3、13 张预期表及关键记录计数。如有端点或提供方凭据，还会用当前加密密钥解开恢复后的对应密钥。成功后生成相邻的私有 `.manifest.json`，保存归档校验和与密钥指纹（不是密钥正文）。复制后运行 `npm run backup:inspect -- <归档路径>` 可在离线环境核对。脚本只删除**该次脚本创建**的临时数据库，原数据库不被覆盖或清空。失败时保留非空备份供排查，可能遗留的临时库名称会在错误输出中显示。

备份验证并不等于远程灾备：应另行把归档、清单和单独加密保管的密钥复制到访问受控的异地位置，并定期演练在新主机、新数据库上恢复后启动应用。流程与尚未解决的生产拦截项见[运维与恢复边界](OPERATIONS.md)。

此脚本只针对本仓库的 Compose 试用环境；不要把其数据库权限设置直接套用到多租户生产部署。已有 PostgreSQL v1/v2 数据可在已验证备份后通过显式开关升级到 v3，见[升级与保留操作](RETENTION.md)；这不是任意版本的在线迁移工具。自动备份轮换和跨区域高可用仍缺失，升级前应保留回滚点。

## 试点准备

受控试点的可执行步骤见[试用记录模板](PILOT.md)。只有在真实场景所有方授权、目标端点可控、数据可脱敏时才接入；不得把本机合成测试称为外部用户或生产成效。
