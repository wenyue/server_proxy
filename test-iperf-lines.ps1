param(
    [string]$Config = "",
    [int]$Time = 10,
    [int]$Parallel = 1,
    [int]$ConnectTimeout = 5000,
    [switch]$NoReverse
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command iperf3 -ErrorAction SilentlyContinue)) {
    Write-Error "iperf3 is required. Install it first and make sure it is in PATH."
}

$python = $env:PYTHON_BIN
if (-not $python) {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $python = "python"
    } elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
        $python = "python3"
    } else {
        Write-Error "Python is required to read the network registry."
    }
}

if ($Time -lt 1) {
    Write-Error "-Time must be a positive integer."
}

if ($Parallel -lt 1) {
    Write-Error "-Parallel must be a positive integer."
}

if ($ConnectTimeout -lt 1) {
    Write-Error "-ConnectTimeout must be a positive integer."
}

if ($Config) {
    if (-not (Test-Path -LiteralPath $Config)) {
        Write-Error "Config file not found: $Config"
    }
    $lines = Import-Csv -LiteralPath $Config
    $configSource = $Config
} else {
    $csvText = & $python script/registry.py iperf-csv 2>&1
    if ($LASTEXITCODE -ne 0) {
        $csvText | ForEach-Object { Write-Error $_ -ErrorAction Continue }
        Write-Error "Failed to load iperf targets from network registry."
    }
    $lines = $csvText | ConvertFrom-Csv
    $configSource = "network registry"
}
$failed = 0
$summary = @()

Write-Host "Running iperf3 line tests"
Write-Host "Config: $configSource"
Write-Host "Duration: ${Time}s per direction"
Write-Host "Parallel streams: $Parallel"
Write-Host "Connect timeout: ${ConnectTimeout}ms"
Write-Host ""

function Get-IperfBitrate {
    param(
        [object[]]$Output
    )

    $sender = ""
    $receiver = ""
    $other = ""

    foreach ($line in $Output) {
        $text = [string]$line
        if ($text -notmatch "bits/sec") {
            continue
        }

        $fields = $text -split "\s+"
        $speed = ""
        for ($i = 1; $i -lt $fields.Count; $i++) {
            if ($fields[$i] -match "bits/sec$") {
                $speed = "$($fields[$i - 1]) $($fields[$i])"
                break
            }
        }

        if (-not $speed) {
            continue
        }

        if ($text -match "receiver") {
            $receiver = $speed
        } elseif ($text -match "sender") {
            $sender = $speed
        } else {
            $other = $speed
        }
    }

    if ($receiver) {
        return $receiver
    }
    if ($sender) {
        return $sender
    }
    if ($other) {
        return $other
    }
    return "n/a"
}

function Invoke-IperfLineTest {
    param(
        [string]$Name,
        [string]$HostName,
        [int]$Port,
        [string]$Direction,
        [switch]$Reverse
    )

    Write-Host "[$Name] $Direction ${HostName}:$Port"

    $args = @("-c", $HostName, "-p", "$Port", "-t", "$Time", "-P", "$Parallel", "--connect-timeout", "$ConnectTimeout")
    if ($Reverse) {
        $args += "--reverse"
    }

    $global:LASTEXITCODE = 0
    $output = & iperf3 @args 2>&1
    $status = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($status -eq 0) {
        Write-Host "[$Name] $Direction OK"
        Write-Host ""
        return [pscustomobject]@{
            Success = $true
            Speed = Get-IperfBitrate -Output $output
        }
    }

    Write-Warning "[$Name] $Direction FAILED"
    Write-Host ""
    return [pscustomobject]@{
        Success = $false
        Speed = "FAILED"
    }
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

    $uploadResult = Invoke-IperfLineTest -Name $line.Name -HostName $line.Host -Port $portNumber -Direction "upload"
    if (-not $uploadResult.Success) {
        $failed++
    }

    $downloadSpeed = "SKIPPED"
    if (-not $NoReverse) {
        $downloadResult = Invoke-IperfLineTest -Name $line.Name -HostName $line.Host -Port $portNumber -Direction "download" -Reverse
        $downloadSpeed = $downloadResult.Speed
        if (-not $downloadResult.Success) {
            $failed++
        }
    }

    $summary += [pscustomobject]@{
        Name = $line.Name
        Host = $line.Host
        Upload = $uploadResult.Speed
        Download = $downloadSpeed
    }
}

if ($summary.Count -gt 0) {
    Write-Host "Summary:"
    $nameWidth = 4
    $hostWidth = 4
    foreach ($row in $summary) {
        if ($row.Name.Length -gt $nameWidth) {
            $nameWidth = $row.Name.Length
        }
        if ($row.Host.Length -gt $hostWidth) {
            $hostWidth = $row.Host.Length
        }
    }

    Write-Host ("{0,-$nameWidth} {1,-$hostWidth} {2,-15} {3,-15}" -f "Name", "Host", "Upload", "Download")
    foreach ($row in $summary) {
        Write-Host ("{0,-$nameWidth} {1,-$hostWidth} {2,-15} {3,-15}" -f $row.Name, $row.Host, $row.Upload, $row.Download)
    }
    Write-Host ""
}

if ($failed -gt 0) {
    Write-Error "Completed $($lines.Count) line(s) with $failed failed test(s)."
}

Write-Host "Completed $($lines.Count) line(s) successfully."
