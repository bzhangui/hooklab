# 演示说明

## 环境

- MoonBit CLI
- Node.js 18+（文件读取、HTML 报告和 HTTP replay 使用 JS CLI）

Windows PowerShell：

```powershell
./scripts/demo.ps1
```

Linux/macOS：

```bash
bash scripts/demo.sh
```

演示依次执行 GitHub 示例签名、验签、JSON 路由、四步重试计划和离线诊断报告。报告生成到 `target/hooklab-demo-report.html`，其中示例邮箱应被替换为 `[REDACTED]`。

## 单项命令

```bash
moon run --target js cmd/hooklab -- retry-plan 5
moon run --target js cmd/hooklab -- route-test @examples/github/payload.json action opened https://worker.example/hook
```

HTTP replay 会产生真实网络请求，只能对本人拥有或明确获准测试的隔离地址使用：

```bash
moon run --target js cmd/hooklab -- replay http://127.0.0.1:8787/webhook @examples/github/payload.json
```

默认演示脚本不会调用 HTTP replay，避免误发数据。
