# 第一个真实本机事件

此流程连接的是你电脑上运行的 HookLab，不是[静态公开演示](https://bzhangui.github.io/hooklab/)。仅向自己控制或明确获准测试的接收端发送事件；没有这样的端点时可先用仓库的合成试点，不得把它写成真实外部试点。

1. 在仓库根目录运行 `npm run doctor`。如果提示 Docker 引擎或本机服务未启动，启动 Docker Desktop，然后运行 `npm run quickstart`；直到 `/health` 就绪。诊断命令只报告本机状态，不打印密钥。
2. 运行 `npm run local:workspace`，在可信电脑上从私有 `.env.portal-local` 获取租户 ID 和 Owner 令牌，连接 `http://127.0.0.1:8787/` 门户。该文件不要上传、截图或发给他人。
3. 在门户依次创建应用、你控制的 HTTPS 接收端点和订阅。订阅的事件类型应包含 `order.created`，或在下方命令中改为订阅的类型。创建应用返回的 `publishToken` **只显示一次**，它与 Owner 令牌不同。
4. 在可信终端将发布令牌放入**当前会话**的 `HOOKLAB_PUBLISH_TOKEN` 环境变量，不要将令牌写入命令参数、脚本或仓库。然后运行：

```text
npm run first:event -- --tenant <租户 ID> --application <应用 ID> --type order.created
```

命令读取 `examples/platform/order-created.json`，生成新的幂等键，只向本机 `127.0.0.1` 发送请求。需要自己的 JSON 时加 `--body <JSON 文件路径>`；单条上限为 1 MiB。命令只输出事件 ID 和交付数量，不打印令牌或正文。随后回到门户刷新，点开事件轨迹。如果显示“已创建交付：0”，先检查订阅是否启用且事件类型匹配。如果事件未成功交付，按[故障排查](OPERATIONS.md)检查签名、接收端 HTTP 响应和死信。

PowerShell 可以用隐藏输入设置会话变量：

```powershell
$secure = Read-Host '粘贴本次应用发布令牌' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $env:HOOKLAB_PUBLISH_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
$tenantId = Read-Host '租户 ID'
$appId = Read-Host '应用 ID'
try { npm run first:event -- --tenant $tenantId --application $appId --type order.created }
finally { Remove-Item Env:HOOKLAB_PUBLISH_TOKEN -ErrorAction SilentlyContinue }
```

环境变量仍可被同一账户的进程读取；它只适合可信本机演示，不是生产密钥管理。不要把真实令牌作为命令行实参或提交到 Git。POSIX shell 可使用 `read -rs HOOKLAB_PUBLISH_TOKEN; export HOOKLAB_PUBLISH_TOKEN`，运行后 `unset HOOKLAB_PUBLISH_TOKEN`。

这条操作路径验证“接收事件→创建交付→门户可查询”，不证明公网 TLS、外部用户采用或生产容量。完整 API、Worker 和至少一次语义见[平台使用说明](PLATFORM.md)。
