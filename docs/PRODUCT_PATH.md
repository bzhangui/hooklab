# 产品路径与 API 兼容策略

## 选用哪个模式

| 需求 | 推荐入口 | 现在的边界 |
| --- | --- | --- |
| 新应用事件与多租户交付 | `serve-platform` | 主推荐路径；PostgreSQL、管理令牌、端点/订阅、消费者门户与跨实例 Worker；先从[本机部署](DEPLOYMENT.md)开始 |
| 单机第三方回调与受信任静态路由 | `serve-config` | SQLite WAL，适合受控单机工具；管理面只允许回环访问，部分限流/熔断状态在进程内 |
| 纯 MoonBit 验签或领域内核 | [Mooncakes 核心库](https://mooncakes.io/docs/bzhangui/hooklab) | `moon add` 安装的是库，不会启动完整 Node.js/PostgreSQL 平台 |

新用户应先看[评审快速上手](REVIEWER_QUICKSTART.md)，再用[六场景公开演示](index.html)理解结果，最后在本机运行真实闭环。不要把静态演示当成在线 HookLab 后端。

## SQLite → PostgreSQL

两个模式**不会自动共享数据库或队列**。现有的[历史转移](MIGRATION.md)只覆盖已结束事件，带私有校验、预览和显式确认；活动交付、配置和密钥不迁移。需要改用平台模式时，应先停止旧模式接收新事件，等待活动队列清空，备份并验证 SQLite，再在 PostgreSQL 中重新配置资源、轮换密钥、核对订阅，最后按范围导入终态历史。任一未清空的活动队列都应中止迁移，不得当作成功切换。自动在线迁移属于后续开发，不在现有能力内。

## 预发布 API 策略

当前模块为 `0.x` 预发布版。接入方应固定 Mooncakes 版本、仓库标签和 API 契约版本，不要依赖未列出的管理字段或数据库表。新增字段应尽量向后兼容；删除或语义变化应在 `CHANGELOG.md` 标出、递增版本，并提供跨版本测试和升级/回滚说明。现有 PostgreSQL schema 只提供受控的 v1/v2→v3 加法迁移；不承诺任意版本零停机升级。收到未知字段或事件版本时，接收端应按自己的契约策略显式处理，而不是静默丢弃。

MoonBit 核心库、Node.js 平台和独立接收端示例的交付边界分别见 [README](../README.md)、[平台使用说明](PLATFORM.md)与[接收端说明](RECEIVER.md)。Node.js 接收端尚未发布到 npm；不要把源码目录导入等同于一个稳定的 npm SDK。
