param(
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"

function Get-PythonExe {
    param([string]$Candidate)

    if ($Candidate) {
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
        throw "Python executable not found: $Candidate"
    }

    $commands = @("python", "py", "python3")
    foreach ($command in $commands) {
        $found = Get-Command $command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
        if ($found) {
            return $found
        }
    }

    throw "Python executable not found. Install Python 3.10+ or pass -PythonExe."
}

$python = Get-PythonExe -Candidate $PythonExe
$requirements = Join-Path $PSScriptRoot "requirements.txt"

Write-Host "Using Python: $python"
& $python -m pip install -r $requirements
if ($LASTEXITCODE -ne 0) {
    throw "pip install failed."
}

Write-Host "Dependencies installed."
