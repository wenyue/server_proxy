param(
    [string]$Config = "config/iperf-lines.csv",
    [int]$Time = 10,
    [int]$Parallel = 1,
    [switch]$NoReverse
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command iperf3 -ErrorAction SilentlyContinue)) {
    Write-Error "iperf3 is required. Install it first and make sure it is in PATH."
}

if (-not (Test-Path -LiteralPath $Config)) {
    Write-Error "Config file not found: $Config"
}

if ($Time -lt 1) {
    Write-Error "-Time must be a positive integer."
}

if ($Parallel -lt 1) {
    Write-Error "-Parallel must be a positive integer."
}

$lines = Import-Csv -LiteralPath $Config
$failed = 0

Write-Host "Running iperf3 line tests"
Write-Host "Config: $Config"
Write-Host "Duration: ${Time}s per direction"
Write-Host "Parallel streams: $Parallel"
Write-Host ""

function Invoke-IperfLineTest {
    param(
        [string]$Name,
        [string]$HostName,
        [int]$Port,
        [string]$Direction,
        [switch]$Reverse
    )

    Write-Host "[$Name] $Direction ${HostName}:$Port"

    $args = @("-c", $HostName, "-p", "$Port", "-t", "$Time", "-P", "$Parallel")
    if ($Reverse) {
        $args += "--reverse"
    }

    & iperf3 @args
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[$Name] $Direction OK"
        Write-Host ""
        return $true
    }

    Write-Warning "[$Name] $Direction FAILED"
    Write-Host ""
    return $false
}

foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line.Name) -or
        [string]::IsNullOrWhiteSpace($line.Host) -or
        [string]::IsNullOrWhiteSpace($line.Port)) {
        Write-Warning "Skipping invalid row: $($line | ConvertTo-Json -Compress)"
        $failed++
        continue
    }

    $portNumber = 0
    if (-not [int]::TryParse($line.Port, [ref]$portNumber)) {
        Write-Warning "Skipping row with invalid port: $($line | ConvertTo-Json -Compress)"
        $failed++
        continue
    }

    if (-not (Invoke-IperfLineTest -Name $line.Name -HostName $line.Host -Port $portNumber -Direction "upload")) {
        $failed++
    }

    if (-not $NoReverse) {
        if (-not (Invoke-IperfLineTest -Name $line.Name -HostName $line.Host -Port $portNumber -Direction "download" -Reverse)) {
            $failed++
        }
    }
}

if ($failed -gt 0) {
    Write-Error "Completed $($lines.Count) line(s) with $failed failed test(s)."
}

Write-Host "Completed $($lines.Count) line(s) successfully."
