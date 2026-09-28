# 评审快速上手

本页只使用合成数据与本机回环地址。HookLab 的 MoonBit 核心库已发布到 Mooncakes；完整事件交付平台是需要自行部署的服务，不是公开网站或生产就绪服务。九项要求和证据入口见[验收清单](ACCEPTANCE.md)。

## 1. 验证公开包可以独立安装（约 1 分钟）

准备 MoonBit CLI 和 Node.js 24+，克隆仓库后在根目录运行：

```bash
node scripts/mooncakes-smoke.mjs 0.3.0-rc.3
```

脚本在系统临时目录创建全新 MoonBit 项目，通过 `moon add` 下载指定的公开版本，导入 `bzhangui/hooklab/hooklab/crypto`，跨目标检查并调用 SHA-256。应输出 `Mooncakes consumer passed`；脚本只清理自己创建的临时目录。使用更新版本时，将命令末尾替换为[注册表](https://mooncakes.io/docs/bzhangui/hooklab)中实际存在的版本号。

## 2. 运行源码 CLI 演示（约 1 分钟）

Windows PowerShell：`./scripts/demo.ps1`；Linux/macOS：`bash scripts/demo.sh`。需要 MoonBit CLI 和 Node.js。演示会对合成 GitHub 负载完成签名、验签、路由、重试计划和脱敏诊断页，并检查示例敏感字段没有写入报告。成功时打印 `HookLab demo completed`，报告保存在 Git 忽略的 `target/` 下。

## 3. 体验完整本机平台（可选）

需要 Node.js 24+、Docker Compose v2 和 MoonBit CLI。在仓库根目录运行 `npm run quickstart`，然后运行 `npm run local:workspace`；按照[部署指南](DEPLOYMENT.md)在本机打开 `http://127.0.0.1:8787/`。生成的 `.env` 与 `.env.portal-local` 是私有凭据，不要上传仓库、截图分享或发给评审。无需在公共网络开放端口。

## 4. 查看自动化证据

[GitHub Actions CI](https://github.com/bzhangui/hooklab/actions/workflows/ci.yml)运行四目标 MoonBit 格式/检查/构建/测试、选定核心包覆盖率门槛、PostgreSQL 双 Worker 与故障接管、容器备份恢复、Windows PowerShell 演示，以及新项目安装 Mooncakes 包的测试。覆盖率门槛针对九个确定性核心包，不代表服务端适配器或全仓库的总体覆盖率。可复现的合成交付流程见[季度评选证据](QUARTERLY_EVIDENCE.md)。目前没有可公开核实的真实外部试点或长期生产 SLO，不作相应宣称。
