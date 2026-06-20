param(
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"

function Ask-Required {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )

    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { "" }
        $value = Read-Host "$Prompt$suffix"
        if (-not $value -and $Default) {
            return $Default
        }
        if ($value) {
            return $value
        }
        Write-Host "This value is required."
    }
}

function Ask-YesNo {
    param(
        [string]$Prompt,
        [bool]$DefaultYes = $true
    )

    $defaultText = if ($DefaultYes) { "Y/n" } else { "y/N" }
    while ($true) {
        $answer = Read-Host "$Prompt ($defaultText)"
        if (-not $answer) {
            return $DefaultYes
        }
        switch ($answer.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
        }
        Write-Host "Please answer y or n."
    }
}

Write-Host "Customs GC331 -> SAP OB08 ZTW1 workflow"
Write-Host ""
Write-Host "Before continuing, prepare:"
Write-Host "1. SAP GUI is open, logged in, and scripting is enabled."
Write-Host "2. Official GC331 Recent TEXT has been downloaded, or it is the newest GC331-like file in Downloads."
Write-Host "3. For Gmail sending, put OAuth credentials.json in runtime\gmail and run install_dependencies.ps1 once."
Write-Host ""

$recipient = ""
$sendEmail = Ask-YesNo "Send Gmail completion notice after SAP verification?" $true
if ($sendEmail) {
    $recipient = Ask-Required "Recipient email"
    $credentialsPath = Join-Path $PSScriptRoot "gmail\credentials.json"
    if (-not (Test-Path -LiteralPath $credentialsPath)) {
        Write-Host "WARNING: gmail\credentials.json was not found. The Gmail step will fail unless this file exists."
        if (-not (Ask-YesNo "Continue anyway?" $false)) {
            throw "Stopped before execution because Gmail credentials are missing."
        }
    }
}

$customsTextFile = Read-Host "GC331 text file path. Leave blank to auto-detect newest GC331 file in Downloads"
if ($customsTextFile -and -not (Test-Path -LiteralPath $customsTextFile)) {
    throw "GC331 text file not found: $customsTextFile"
}
if (-not $customsTextFile) {
    if (-not (Ask-YesNo "Confirm the newest GC331 Recent TEXT file is already in Downloads" $true)) {
        throw "Stopped before execution because GC331 text file is not ready."
    }
}

if (-not (Ask-YesNo "Confirm SAP GUI is logged in and ready for OB08" $false)) {
    throw "Stopped before execution because SAP GUI is not ready."
}

$rateType = Ask-Required "SAP exchange rate type" "ZTW1"
$toCurrency = Ask-Required "Target currency" "TWD"
$currencies = Ask-Required "Source currencies comma-separated" "USD,EUR,JPY,CNY"

Write-Host ""
Write-Host "Execution summary:"
Write-Host "Rate type: $rateType"
Write-Host "Target currency: $toCurrency"
Write-Host "Source currencies: $currencies"
Write-Host "GC331 file: $(if ($customsTextFile) { $customsTextFile } else { 'auto-detect from Downloads' })"
Write-Host "Gmail: $(if ($sendEmail) { "send to $recipient" } else { 'disabled' })"
Write-Host ""

if (-not (Ask-YesNo "Run SAP update now?" $false)) {
    throw "Stopped by user before SAP update."
}

$main = Join-Path $PSScriptRoot "run_customs_fx_ztw1_update.ps1"
$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $main,
    "-RateType", $rateType,
    "-ToCurrency", $toCurrency,
    "-Currencies", $currencies
)

if ($customsTextFile) {
    $argsList += @("-CustomsTextFile", $customsTextFile)
}
if ($PythonExe) {
    $argsList += @("-PythonExe", $PythonExe)
}
if ($sendEmail) {
    $argsList += @("-Recipient", $recipient)
}
else {
    $argsList += "-NoEmail"
}

& powershell @argsList
exit $LASTEXITCODE
