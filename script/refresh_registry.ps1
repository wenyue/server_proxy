param(
    [switch]$ReloadNginx
)

$ErrorActionPreference = "Stop"

$python = $env:PYTHON_BIN
if (-not $python) {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $python = "python"
    } elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
        $python = "python3"
    } else {
        throw "Python is required to refresh the network registry outputs."
    }
}

$argsList = @("script/registry.py", "refresh")
if ($ReloadNginx) {
    $argsList += "--reload-nginx"
}

& $python @argsList
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
