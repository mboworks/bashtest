# Verify that tests bootstrap their own Bash and Unix utilities.
$ErrorActionPreference = 'Stop'
$bazel = (Get-Command bazel).Source
$env:PATH = "$env:SystemRoot\system32;$env:SystemRoot"
Remove-Item Env:BAZEL_SH -ErrorAction SilentlyContinue
$env:MSYS_NO_PATHCONV = '1'
foreach ($name in @('bash', 'grep', 'sed', 'diff')) {
    if (Get-Command $name -ErrorAction SilentlyContinue) { throw "Unexpected installed tool: $name" }
}
& $bazel test //...
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $bazel test --enable_runfiles=no //...
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $bazel run --enable_runfiles=no //bashtest/tests:runtime_test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# Drive the existing external-consumer tests with the downloaded interpreter.
$execRoot = & $bazel info execution_root
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$bashFile = & $bazel cquery '@bashtest_windows_runtime//:usr/bin/bash.exe' --output=files
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$bash = Join-Path $execRoot $bashFile
$env:PATH = "$(Split-Path $bash);$(Split-Path $bazel);$env:PATH"
& $bash bashtest/tests/external_consumer_test.sh
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $bash bashtest/tests/tools_consumer_test.sh
exit $LASTEXITCODE
