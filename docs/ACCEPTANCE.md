# HookLab 验收清单与 Mooncakes 发布

本页按九项验收要求记录可复核入口。`bzhangui/hooklab` 已发布到 Mooncakes；最新版本与实际状态以公开 GitHub CI 和 Mooncakes 注册表为准。本地合成测试不代表真实外部试点或生产性能。

| 要求 | 核验入口 |
| --- | --- |
| MoonBit 为主要实现语言，`moonc >= 0.10.14` | `hooklab/*` 的领域内核与 `docs/MOONBIT_CORE.md` 的真实调用链；`node scripts/check-moonc-version.mjs`；CI 的 Toolchain 和版本门槛步骤 |
| 公开 GitHub 与连续提交 | [公开仓库](https://github.com/bzhangui/hooklab)及其提交历史；提交须区分功能、测试和文档 |
| 结构与声明功能 | `README.md` 的项目结构、`docs/ARCHITECTURE.md`、网关和 PostgreSQL 端到端测试 |
| README 可安装、可使用、可复现 | `README.md` 的本机快速启动、CLI 示例和验证命令；`docs/DEPLOYMENT.md`、`docs/PLATFORM.md` |
| CI 检查、构建、测试 | `.github/workflows/ci.yml`：四目标格式/检查/单测/构建、选定核心包覆盖率门槛、Windows 演示、公开包独立安装、网关与 PostgreSQL 集成、容器部署和恢复 |
| 可运行示例 | [公开的合成交互页](https://bzhangui.github.io/hooklab/)、[评审快速上手](REVIEWER_QUICKSTART.md)、`scripts/demo.sh` / `scripts/demo.ps1`、`examples/`、`scripts/platform-showcase.mjs`；静态页面不等于运行后端 |
| 核心路径测试 | `moon test --target all --deny-warn`、`node scripts/check-core-coverage.mjs`、`npm run test:platform`、网关和 PostgreSQL 端到端脚本、[多角色合成试点](SIMULATED_PILOT.md)；生产试点不在已有证据内 |
| 发布到 mooncakes.io | **已完成**：[公开模块页](https://mooncakes.io/docs/bzhangui/hooklab)；`moon view bzhangui/hooklab --json` 可查最新版本、MIT 许可证和仓库地址；`node scripts/mooncakes-smoke.mjs` 在独立新项目安装并调用 `hooklab/crypto` |
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

新增范围在[提交 `e6921f0` 的五作业 CI](https://github.com/bzhangui/hooklab/actions/runs/36429210008)通过：Linux 完整检查、Windows 冒烟、隔离容器部署与备份恢复、已发布包的独立安装，以及三轮多角色合成档。CI 通过不表示真实外部用户试点、公网安全审计或长时生产稳定性已经完成。

后续维护增加 `npm run doctor`、[首个事件闭环](FIRST_EVENT.md)、精确目标主机白名单，以及可手动触发的[10/30 轮合成重复性验证](CAPACITY_PROTOCOL.md)。这些改动须以当次提交的 CI 结果为准；手动重复性工作流提供回归证据，不替代真实用户、生产容量或异地灾备结果。

## 发布与独立安装核验

账号 `bzhangui` 已完成注册。当前 `0.3.0-rc.5` 于 2026-09-28 发布：`moon publish --frozen` 返回 `200 OK`；`moon view bzhangui/hooklab@0.3.0-rc.5 --json` 返回 `status: success`、MIT 许可证和正确的 GitHub 仓库地址。[GitHub 预发布标签](https://github.com/bzhangui/hooklab/releases/tag/v0.3.0-rc.5)指向通过[五作业 CI](https://github.com/bzhangui/hooklab/actions/runs/36429819183)的 `04d0d08`。不要将 `~/.moon/credentials.json`、登录令牌或任何授权码提交、上传或分享。

在隔离的新 MoonBit 项目中，`node scripts/mooncakes-smoke.mjs` 会查询最新公开版本并通过 `moon add` 下载；将 `"bzhangui/hooklab/hooklab/crypto" @crypto` 加入可执行包的 `moon.pkg`，在 `main.mbt` 中运行 `println(@crypto.sha256_hex("abc"))`，应输出 `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`，且 `moon check --target all --deny-warn` 通过。`0.3.0-rc.5` 的显式固定版本已复核通过，CI 会持续验证它；这证明公开包可独立安装和调用，不等于完整 Node.js 平台服务已通过外部真实试点。

Mooncakes 的 `rc.3` 历史归档是发布时快照，内含旧 README 的“尚未发布”描述；该描述已过时，不能通过改动 GitHub 上的 README 覆盖同一已发布版本。`rc.4` 起改为版本无关 README；页面另有“尚未发布到 npm”，指的是独立 Node.js SDK，不是 Mooncakes 包。每次发布必须递增 `moon.mod` 版本，并重复上述安全检查与独立安装核验。
