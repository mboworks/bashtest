# Verify that tests bootstrap their own Bash and Unix utilities.
$ErrorActionPreference = 'Stop'
# Use one native launcher: PowerShell script parameter binding consumes --.
$bazel = (Get-Command bazel -CommandType Application | Select-Object -First 1).Source
function Invoke-TestBazel([string] $name, [string[]] $bazelArgs) {
    if (-not $env:BASHTEST_CI_REPORTS) {
        & $bazel @bazelArgs
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        return
    }
    $output = Join-Path $env:BASHTEST_CI_REPORTS $name
    New-Item -ItemType Directory -Path $output -ErrorAction Stop | Out-Null
    $events = Join-Path $output 'events.json'
    $command = @($bazelArgs[0], "--build_event_json_file=$events") + $bazelArgs[1..($bazelArgs.Count - 1)]
    & $bazel @command 2>&1 | Tee-Object -FilePath (Join-Path $output 'command.log')
    $status = $LASTEXITCODE
    & $bazel run //tools:ci_reports -- collect --events $events --output $output --exit-code $status
    $collectionStatus = $LASTEXITCODE
    if ($status -ne 0) { exit $status }
    if ($collectionStatus -ne 0) { exit $collectionStatus }
}
# Hosted runners install Bazelisk through npm; retain its Node launcher only.
$nodeDirectory = Split-Path (Get-Command node).Source
# Exclude System32 too: it can contain the WSL bash.exe forwarding stub.
$env:PATH = "$nodeDirectory;$env:SystemRoot"
Remove-Item Env:BAZEL_SH -ErrorAction SilentlyContinue
$env:MSYS_NO_PATHCONV = '1'
foreach ($name in @('bash', 'grep', 'sed', 'diff')) {
    if (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue) { throw "Unexpected installed tool: $name" }
}
Invoke-TestBazel 'root-default' @('test', '//...')
Invoke-TestBazel 'root-manifest' @('test', '--enable_runfiles=no', '//...')
Invoke-TestBazel 'root-runtime' @('run', '--enable_runfiles=no', '//bashtest/tests:runtime_test')
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
