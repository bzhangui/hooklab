$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Force target | Out-Null
    $payload = '@examples/github/payload.json'
    $signature = (& moon run --target js cmd/hooklab -- sign github test-secret $payload).Trim()
    if (-not $signature.StartsWith('sha256=')) { throw 'Signing did not return a GitHub signature.' }

    & moon run --target js cmd/hooklab -- verify github test-secret $payload $signature
    if ($LASTEXITCODE -ne 0) { throw 'Verification demo failed.' }
    & moon run --target js cmd/hooklab -- route-test $payload action opened https://worker.example/hook
    if ($LASTEXITCODE -ne 0) { throw 'Routing demo failed.' }
    & moon run --target js cmd/hooklab -- retry-plan 4
    if ($LASTEXITCODE -ne 0) { throw 'Retry demo failed.' }
    & moon run --target js cmd/hooklab -- report github test-secret $payload $signature target/hooklab-demo-report.html
    if ($LASTEXITCODE -ne 0) { throw 'Report demo failed.' }

    $report = Get-Content -Raw target/hooklab-demo-report.html
    if ($report.Contains('must-not-appear@example.invalid')) { throw 'Sensitive example value leaked into report.' }
    if (-not $report.Contains('[REDACTED]')) { throw 'Expected redaction marker was not found.' }
    Write-Host 'HookLab demo completed; report: target/hooklab-demo-report.html'
} finally {
    Pop-Location
}
