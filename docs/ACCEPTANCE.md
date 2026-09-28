# HookLab 验收清单与 Mooncakes 发布

本页按九项验收要求记录可复核入口。`bzhangui/hooklab@0.3.0-rc.3` 已于 2026-09-28 发布到 Mooncakes；实际状态以公开 GitHub CI 和 Mooncakes 注册表为准。本地合成测试不代表真实外部试点或生产性能。

| 要求 | 核验入口 |
| --- | --- |
| MoonBit 为主要实现语言，`moonc >= 0.10.14` | `hooklab/*` 的领域内核与 `docs/MOONBIT_CORE.md` 的真实调用链；`node scripts/check-moonc-version.mjs`；CI 的 Toolchain 和版本门槛步骤 |
| 公开 GitHub 与连续提交 | [公开仓库](https://github.com/bzhangui/hooklab)及其提交历史；提交须区分功能、测试和文档 |
| 结构与声明功能 | `README.md` 的项目结构、`docs/ARCHITECTURE.md`、网关和 PostgreSQL 端到端测试 |
| README 可安装、可使用、可复现 | `README.md` 的本机快速启动、CLI 示例和验证命令；`docs/DEPLOYMENT.md`、`docs/PLATFORM.md` |
| CI 检查、构建、测试 | `.github/workflows/ci.yml`：四目标格式/检查/单测/构建、选定核心包覆盖率门槛、Windows 演示、公开包独立安装、网关与 PostgreSQL 集成、容器部署和恢复 |
| 可运行示例 | [评审快速上手](REVIEWER_QUICKSTART.md)、`scripts/demo.sh` / `scripts/demo.ps1`、`examples/`、`scripts/platform-showcase.mjs` |
| 核心路径测试 | `moon test --target all --deny-warn`、`node scripts/check-core-coverage.mjs`、`npm run test:platform`、网关和 PostgreSQL 端到端脚本；生产试点不在已有证据内 |
| 发布到 mooncakes.io | **已完成**：[公开模块页](https://mooncakes.io/docs/bzhangui/hooklab)；`moon view bzhangui/hooklab@0.3.0-rc.3 --json` 返回 `success`、MIT 许可证和仓库地址；独立新项目安装并调用 `hooklab/crypto` 成功 |
| OSI 许可证与第三方兼容 | 根目录 `LICENSE` (MIT)、`moon.mod` 的 MIT 字段和 `THIRD_PARTY_NOTICES.md` |

## 发布前安全检查

MoonBit 官方要求发布模块名以 Mooncakes 用户名开头。本仓库当前名称为 `bzhangui/hooklab`；若注册时无法使用 `bzhangui`，必须先统一修改模块名及内部包导入、重新运行全部测试，不能用别人的账号直接发布。

`moon package` 原先会包含仓库根目录的《项目申报书.md》，即使该文件有未提交修改。因此 `.moonignore` 显式排除申报材料，且复制了 `.gitignore` 的私有文件规则。每次发布前运行：

```bash
node scripts/check-moonc-version.mjs
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --deny-warn
node scripts/check-core-coverage.mjs
npm run test:platform
node scripts/check-package-contents.mjs
```

最后一条命令调用 `moon package --list --frozen` 并拒绝把申报材料、`.env`、备份或依赖目录装入公开归档。不要把真实密钥、回调正文或数据库归档提交到 GitHub 或 Mooncakes。

## 发布与独立安装核验

账号 `bzhangui` 已完成注册。`moon publish --frozen` 的服务端结果为 `200 OK`；独立执行 `moon view bzhangui/hooklab@0.3.0-rc.3 --json` 返回 `status: success`，版本 `0.3.0-rc.3`、MIT 许可证及 GitHub 仓库链接均正确。不要将 `~/.moon/credentials.json`、登录令牌或任何授权码提交、上传或分享。

在仓库 `_build/` 下新建的隔离 MoonBit 项目中，`moon add bzhangui/hooklab@0.3.0-rc.3` 从注册表下载成功；将 `"bzhangui/hooklab/hooklab/crypto" @crypto` 加入可执行包的 `moon.pkg`，在 `main.mbt` 中运行 `println(@crypto.sha256_hex("abc"))`，输出 `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`，且 `moon check --target all --deny-warn` 通过。这验证了公开包可独立安装和调用，不等于完整 Node.js 平台服务已通过外部真实试点。

Mooncakes 的 `rc.3` 发布归档是发布时快照，内含旧 README 的“尚未发布”描述；该描述已过时，不能通过改动 GitHub 上的 README 覆盖同一已发布版本。当前状态以注册表查询和本页为准，下一次递增版本发布时再修正包内快照。后续发布必须递增 `moon.mod` 版本，并重复上述安全检查与独立安装核验。
