# Verify that tests bootstrap their own Bash and Unix utilities.
$ErrorActionPreference = 'Stop'
# Use one native launcher: PowerShell script parameter binding consumes --.
$bazel = (Get-Command bazel -CommandType Application | Select-Object -First 1).Source
# Hosted runners install Bazelisk through npm; retain its Node launcher only.
$nodeDirectory = Split-Path (Get-Command node).Source
# Exclude System32 too: it can contain the WSL bash.exe forwarding stub.
$env:PATH = "$nodeDirectory;$env:SystemRoot"
Remove-Item Env:BAZEL_SH -ErrorAction SilentlyContinue
$env:MSYS_NO_PATHCONV = '1'
foreach ($name in @('bash', 'grep', 'sed', 'diff')) {
    if (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue) { throw "Unexpected installed tool: $name" }
}
# Build events are independent of test execution; the always-run workflow step
# collects a failed command's outputs too.
$reports = if ($env:BASHTEST_CI_REPORTS) { $env:BASHTEST_CI_REPORTS } else { Join-Path $env:TEMP ([guid]::NewGuid().ToString()) }
New-Item -ItemType Directory -Path $reports -Force | Out-Null
& $bazel test //... "--build_event_json_file=$reports/root-default.json"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $bazel run //tools:ci_reports -- collect --events "$reports/root-default.json" --output "$reports/root-default"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $bazel test --enable_runfiles=no //... "--build_event_json_file=$reports/root-manifest.json"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $bazel run //tools:ci_reports -- collect --events "$reports/root-manifest.json" --output "$reports/root-manifest"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $bazel run --enable_runfiles=no //bashtest/tests:runtime_test "--build_event_json_file=$reports/root-runtime.json"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# Drive the existing external-consumer tests with the downloaded interpreter.
# Resolve the downloaded source, not an execroot link pruned by later builds.
$outputBase = & $bazel info output_base
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$bashFile = & $bazel cquery '@bashtest_windows_runtime//:usr/bin/bash.exe' --output=files
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$bash = Join-Path $outputBase $bashFile
$env:PATH = "$(Split-Path $bash);$(Split-Path $bazel);$env:PATH"
& $bash bashtest/tests/external_consumer_test.sh
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $bash bashtest/tests/tools_consumer_test.sh
exit $LASTEXITCODE
