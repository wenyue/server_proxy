$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("iperf-lines-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$oldPath = $env:PATH
$oldPythonBin = $env:PYTHON_BIN

try {
    Set-Content -LiteralPath (Join-Path $tmpDir "iperf3.ps1") -Encoding UTF8 -Value @'
$hostName = ""
$reverse = $false
$connectTimeout = ""

for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "-c" {
            $hostName = $args[$i + 1]
            $i++
        }
        "--connect-timeout" {
            $connectTimeout = $args[$i + 1]
            $i++
        }
        "--reverse" {
            $reverse = $true
        }
    }
}

if ($connectTimeout -ne "5000") {
    Write-Error "missing connect timeout"
    exit 2
}

if ($hostName -eq "203.0.113.10" -and -not $reverse) {
    Write-Output "[  5]   0.00-1.00   sec  12.0 MBytes   100 Mbits/sec  receiver"
} elseif ($hostName -eq "203.0.113.10") {
    Write-Output "[  5]   0.00-1.00   sec  24.0 MBytes   200 Mbits/sec  receiver"
} elseif ($hostName -eq "2001:db8::1" -and -not $reverse) {
    Write-Output "[SUM]   0.00-1.00   sec   128 MBytes  1.00 Gbits/sec  receiver"
} elseif ($hostName -eq "2001:db8::1") {
    Write-Output "[SUM]   0.00-1.00   sec  76.8 MBytes   600 Mbits/sec  receiver"
} else {
    exit 1
}
'@

    $targets = Join-Path $tmpDir "targets.csv"
    Set-Content -LiteralPath $targets -Encoding UTF8 -Value @'
Name,Host,Port
node-a,203.0.113.10,5201
node-b,2001:db8::1,5201
'@

    $env:PATH = "$tmpDir;$oldPath"
    $scriptPath = Join-Path $rootDir "test-iperf-lines.ps1"
    $output = & pwsh -NoLogo -NoProfile -File $scriptPath -Config $targets -Time 1 -ConnectTimeout 5000 2>&1 | Out-String
    $status = $LASTEXITCODE

    if ($status -ne 0) {
        throw "expected summary run to pass, got exit code $status`n$output"
    }
    if ($output -notmatch "Summary:") {
        throw "missing summary header`n$output"
    }
    if ($output -notmatch "Name\s+Host\s+Upload\s+Download") {
        throw "missing summary columns`n$output"
    }
    if ($output -notmatch "node-a\s+203\.0\.113\.10\s+100 Mbits/sec\s+200 Mbits/sec") {
        throw "missing node-a speeds`n$output"
    }
    if ($output -notmatch "node-b\s+2001:db8::1\s+1\.00 Gbits/sec\s+600 Mbits/sec") {
        throw "missing node-b speeds`n$output"
    }

    Set-Content -LiteralPath (Join-Path $tmpDir "python.ps1") -Encoding UTF8 -Value @'
[Console]::Error.WriteLine("registry failed")
exit 42
'@
    $env:PYTHON_BIN = "python"

    $failureOutput = & pwsh -NoLogo -NoProfile -File $scriptPath -Time 1 2>&1 | Out-String
    $failureStatus = $LASTEXITCODE
    if ($failureStatus -eq 0) {
        throw "expected registry failure to exit nonzero"
    }
    if ($failureOutput -notmatch "registry failed") {
        throw "missing registry stderr`n$failureOutput"
    }
    if ($failureOutput -notmatch "Failed to load iperf targets from network registry.") {
        throw "missing registry failure message`n$failureOutput"
    }
    if ($failureOutput -match "Completed 0 line\(s\) successfully\.") {
        throw "script reported success after registry failure`n$failureOutput"
    }
} finally {
    $env:PATH = $oldPath
    if ($null -eq $oldPythonBin) {
        Remove-Item Env:\PYTHON_BIN -ErrorAction SilentlyContinue
    } else {
        $env:PYTHON_BIN = $oldPythonBin
    }
    Remove-Item -LiteralPath $tmpDir -Recurse -Force
}
