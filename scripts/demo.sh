#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
mkdir -p target

payload='@examples/github/payload.json'
signature="$(moon run --target js cmd/hooklab -- sign github test-secret "$payload" | tail -n 1)"
case "$signature" in sha256=*) ;; *) echo 'Signing did not return a GitHub signature.' >&2; exit 1 ;; esac

moon run --target js cmd/hooklab -- verify github test-secret "$payload" "$signature"
moon run --target js cmd/hooklab -- route-test "$payload" action opened https://worker.example/hook
moon run --target js cmd/hooklab -- retry-plan 4
moon run --target js cmd/hooklab -- report github test-secret "$payload" "$signature" target/hooklab-demo-report.html

if grep -Fq 'must-not-appear@example.invalid' target/hooklab-demo-report.html; then
  echo 'Sensitive example value leaked into report.' >&2
  exit 1
fi
grep -Fq '[REDACTED]' target/hooklab-demo-report.html
echo 'HookLab demo completed; report: target/hooklab-demo-report.html'
