# HookLab 验收清单与 Mooncakes 发布

本页按九项验收要求记录可复核入口。`0.3.0-rc.3` 是当前源码的发布候选版本，不等于已经发布；实际结果以公开 GitHub CI 和 Mooncakes 页面为准。本地合成测试不代表真实外部试点或生产性能。

| 要求 | 核验入口 |
| --- | --- |
| MoonBit 为主要实现语言，`moonc >= 0.10.14` | `hooklab/*` 的领域内核与 `docs/MOONBIT_CORE.md` 的真实调用链；`node scripts/check-moonc-version.mjs`；CI 的 Toolchain 和版本门槛步骤 |
| 公开 GitHub 与连续提交 | [公开仓库](https://github.com/bzhangui/hooklab)及其提交历史；提交须区分功能、测试和文档 |
| 结构与声明功能 | `README.md` 的项目结构、`docs/ARCHITECTURE.md`、网关和 PostgreSQL 端到端测试 |
| README 可安装、可使用、可复现 | `README.md` 的本机快速启动、CLI 示例和验证命令；`docs/DEPLOYMENT.md`、`docs/PLATFORM.md` |
| CI 检查、构建、测试 | `.github/workflows/ci.yml`：四目标格式/检查/单测/构建、网关与 PostgreSQL 集成、容器部署和恢复 |
| 可运行示例 | `scripts/demo.sh` / `scripts/demo.ps1`、`examples/`、`scripts/platform-showcase.mjs` |
| 核心路径测试 | `moon test --target all --deny-warn`、`npm run test:platform`、网关和 PostgreSQL 端到端脚本；生产试点不在已有证据内 |
| 发布到 mooncakes.io | **待完成**：必须由模块名对应账号登录、执行 `moon publish`，再检查公开模块页和从新项目安装 |
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
npm run test:platform
node scripts/check-package-contents.mjs
```

最后一条命令调用 `moon package --list --frozen` 并拒绝把申报材料、`.env`、备份或依赖目录装入公开归档。不要把真实密钥、回调正文或数据库归档提交到 GitHub 或 Mooncakes。

## 需要账号持有人完成的发布步骤

1. 在可信设备上运行 `moon register`，完成 Mooncakes 账号注册，选择与模块名前缀一致的用户名；随后运行 `moon login`。不要把密码、登录令牌或 `~/.moon/credentials.json` 发给任何人。
2. 在干净且通过上述检查的源码上运行 `moon publish --dry-run --frozen`，审查返回信息，再运行 `moon publish --frozen`。公开发布是不可替代的独立步骤，GitHub 推送不会自动完成它。
3. 用 `moon view bzhangui/hooklab@0.3.0-rc.3 --json` 与公开模块页面核对版本、许可证和仓库链接；在全新项目中执行 `moon add bzhangui/hooklab@0.3.0-rc.3` 并构建最小导入示例。完成后才更新本页及 README 的“待完成”状态。

若注册账号名不同，先停止发布并调整模块命名。本页不把未执行的发布或安装验收写作已完成。
