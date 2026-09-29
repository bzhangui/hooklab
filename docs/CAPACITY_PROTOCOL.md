# 受控重复性与容量验证

当前有 32 条并发发布的合成展示脚本，以及每轮覆盖多租户、额度、故障接管的可重复试点。它们可以发现回归，**不能**推导公网吞吐、生产 P99、真实用户可用性或跨主机容灾。每轮重新使用专用的 `hooklab_test` 测试库；不得对含真实数据的库运行。

## 可执行的受控验证

- 代码提交运行常规五作业 CI，其中 `simulated-pilot` 重复三轮。
- 手动触发 `Synthetic repeatability` 工作流，选择 10 或 30 轮。它只连接 GitHub Actions 的一次性 PostgreSQL 服务，失败时中止并保留脱敏汇总。仓库所有者也可在受控本机设置 `TEST_DATABASE_URL` 指向独立的 `hooklab_test` 库，运行 `node scripts/simulated-pilot.mjs --profile full --repeat 30`。
- 比较两次结果时必须固定 Git 提交、Node/MoonBit/PostgreSQL 版本、机器规格和重复数。记录全部场景通过率、发布请求 P50/P95、批量完成时间与租约接管耗时；有任一轮失败就不能报告为通过。不能把不同 CI 宿主机的微小延迟差解释为代码优化。
- 在得到授权的独立环境之前，不向真实外部接收端发流量。若以后部署到受控公网，应另测多小时/多日连续负载、峰值速率、队列积压、进程 RSS、数据库/备份增长、网络失败、跨主机恢复时间及成本，并定义符合场景的 SLO 与退出阈值。

原始汇总在 Git 忽略的 `target/simulated-pilot-report.json`，仅含白名单中的合成数字与场景状态；失败日志位于私有 `target/`，不要上传原始正文或密钥。比较和公开结果时明确标注“合成回环环境”，不能称为真实试点或生产压测。

## 2026-09-29 受控重复性记录

[GitHub Actions 运行记录](https://github.com/bzhangui/hooklab/actions/runs/36566633026)使用提交 `ad17b31`、Ubuntu 24.04、Node.js 24 和一次性 PostgreSQL 17，执行 `--profile full --repeat 30`，结果为 **99/99 场景组通过，失败 0 组**。其中 30 次合成展示各执行 32 条并发发布；各轮发布请求 P95 的范围是 **96–118 ms**，各轮批量完成耗时范围是 **301–325 ms**。运行页的 `synthetic-repeatability-summary` artifact 仅包含角色、场景名、轮次、通过状态、耗时和白名单中的合成样本数字。

这些数字只用于同类 CI 环境回归比较。它们未测量持续峰值吞吐、生产 P99、进程 RSS、数据库增长、跨主机恢复或真实外部接收方效果，因此不能作为生产容量承诺。
