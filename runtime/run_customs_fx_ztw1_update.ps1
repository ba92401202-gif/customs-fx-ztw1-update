param(
    [string]$Recipient = "",
    [string]$CustomsTextFile = "",
    [string]$OutputDir = (Join-Path $PSScriptRoot "output"),
    [string]$RateType = "ZTW1",
    [string]$ToCurrency = "TWD",
    [string]$Currencies = "USD,EUR,JPY,CNY",
    [string]$PythonExe = "",
    [switch]$NoEmail
)

$ErrorActionPreference = "Stop"

function Get-PythonExe {
    if ($PythonExe) {
        if (Test-Path -LiteralPath $PythonExe) {
            return $PythonExe
        }
        throw "Python executable not found: $PythonExe"
    }

    $candidates = @(
        (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        (Get-Command py -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        (Get-Command python3 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
    ) | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw "Python executable not found."
}

function Invoke-CscriptFile {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $cmd = @("//nologo", $ScriptPath) + $Arguments
    & cscript @cmd | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "VBS failed: $ScriptPath"
    }
}

function Find-LatestCustomsTextFile {
    $downloadDir = Join-Path $env:USERPROFILE "Downloads"
    if (-not (Test-Path -LiteralPath $downloadDir)) {
        throw "Downloads folder not found. Pass -CustomsTextFile."
    }

    $candidates = Get-ChildItem -LiteralPath $downloadDir -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 50

    foreach ($file in $candidates) {
        if ($file.Length -gt 200KB) { continue }
        try {
            $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            if ($text -match "USD\s+\d+\s+\d+\s+\d+\s+" -and $text -match "EUR\s+\d+\s+\d+\s+\d+\s+") {
                return $file.FullName
            }
        }
        catch {
            continue
        }
    }
    throw "No recent GC331 text file found in Downloads. Download Recent TEXT first or pass -CustomsTextFile."
}

function Parse-PositionCheck {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = @{}
    $current = $null
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match "^CHECK\s+([A-Z]{3})$") {
            $current = $matches[1]
            $result[$current] = @()
            continue
        }
        if ($current -and $line -match "^\s*row=(\d+)\s+([^/]+)\/(\d{4}\/\d{2}\/\d{2})\/([A-Z]{3})\/([A-Z]{3})\s+KURSM=(.*?)\s+KURSP=(.*?)\s+FFACT=(.*?)\s+TFACT=(.*?)$") {
            $result[$current] += [pscustomobject]@{
                Row = [int]$matches[1]
                RateType = $matches[2].Trim()
                ValidFrom = $matches[3].Trim()
                FromCurrency = $matches[4].Trim()
                ToCurrency = $matches[5].Trim()
                KURSM = $matches[6].Trim()
                KURSP = $matches[7].Trim()
                FFACT = $matches[8].Trim()
                TFACT = $matches[9].Trim()
            }
        }
    }
    return $result
}

function Get-TargetRows {
    param(
        [hashtable]$Parsed,
        [string]$Currency,
        [string]$RateType,
        [string]$ValidFrom,
        [string]$ToCurrency
    )

    if (-not $Parsed.ContainsKey($Currency)) { return @() }
    return @($Parsed[$Currency] | Where-Object {
        $_.RateType -eq $RateType -and
        $_.ValidFrom -eq $ValidFrom -and
        $_.FromCurrency -eq $Currency -and
        $_.ToCurrency -eq $ToCurrency
    })
}

function Get-Rate {
    param(
        [pscustomobject]$ParsedRates,
        [string]$Currency
    )
    return [string]$ParsedRates.rates.$Currency.purchase_in
}

function Test-RateEqual {
    param(
        [string]$Actual,
        [string]$Expected
    )

    $actualValue = [decimal]::Parse($Actual, [Globalization.CultureInfo]::InvariantCulture)
    $expectedValue = [decimal]::Parse($Expected, [Globalization.CultureInfo]::InvariantCulture)
    return ($actualValue -eq $expectedValue)
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if (-not $NoEmail -and -not $Recipient) {
    throw "Recipient is required unless -NoEmail is used."
}

$scriptsDir = Join-Path $PSScriptRoot "scripts"
$gmailDir = Join-Path $PSScriptRoot "gmail"
$pythonExe = Get-PythonExe

if (-not $CustomsTextFile) {
    $CustomsTextFile = Find-LatestCustomsTextFile
}
if (-not (Test-Path -LiteralPath $CustomsTextFile)) {
    throw "Customs text file not found: $CustomsTextFile"
}

$parseOut = Join-Path $OutputDir "customs_gc331_latest.json"
& $pythonExe (Join-Path $scriptsDir "parse_customs_gc331_text.py") $CustomsTextFile --currencies $Currencies --json-out $parseOut | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to parse GC331 text file."
}

$parsedRates = Get-Content -LiteralPath $parseOut -Raw -Encoding UTF8 | ConvertFrom-Json
$validFrom = $parsedRates.valid_from
$currList = @($Currencies.Split(",") | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })

$probeOut = Join-Path $OutputDir "sap_probe.txt"
$navOut = Join-Path $OutputDir "ob08_nav.txt"
$checkBeforeOut = Join-Path $OutputDir "ob08_position_before.txt"
$sapActionOut = Join-Path $OutputDir "ob08_action.txt"
$checkAfterOut = Join-Path $OutputDir "ob08_position_after.txt"
$resultFile = Join-Path $OutputDir ("customs_ztw1_update_{0}.txt" -f (($validFrom -replace "/", "")))

Invoke-CscriptFile -ScriptPath (Join-Path $scriptsDir "sap_gui_probe.vbs") -Arguments @($probeOut)
$probeText = Get-Content -LiteralPath $probeOut -Encoding UTF8 -Raw
if ($probeText -match "ERROR:") {
    throw "SAP GUI unavailable: $probeText"
}

Invoke-CscriptFile -ScriptPath (Join-Path $scriptsDir "sap_gui_go_tcode.vbs") -Arguments @("OB08", $navOut)
Invoke-CscriptFile -ScriptPath (Join-Path $scriptsDir "sap_gui_ob08_position_check_ztw1.vbs") -Arguments @($checkBeforeOut, $validFrom, $RateType, ($currList -join ","))

$before = Parse-PositionCheck -Path $checkBeforeOut
$counts = @{}
foreach ($curr in $currList) {
    $counts[$curr] = @(Get-TargetRows -Parsed $before -Currency $curr -RateType $RateType -ValidFrom $validFrom -ToCurrency $ToCurrency).Count
}
$counts | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDir "ob08_target_counts_before.json") -Encoding UTF8

if (($counts.Values | Measure-Object -Maximum).Maximum -gt 1) {
    throw "Duplicate OB08 target key detected. Counts=$($counts | ConvertTo-Json -Compress)"
}

$allMissing = $true
$allExisting = $true
foreach ($curr in $currList) {
    if ($counts[$curr] -ne 0) { $allMissing = $false }
    if ($counts[$curr] -ne 1) { $allExisting = $false }
}
if (-not ($allMissing -or $allExisting)) {
    throw "Mixed OB08 target key state detected. Counts=$($counts | ConvertTo-Json -Compress)"
}

$usdRate = Get-Rate $parsedRates "USD"
$eurRate = Get-Rate $parsedRates "EUR"
$jpyRate = Get-Rate $parsedRates "JPY"
$cnyRate = Get-Rate $parsedRates "CNY"

if ($allMissing) {
    Invoke-CscriptFile -ScriptPath (Join-Path $scriptsDir "sap_gui_ob08_open_new_dump.vbs") -Arguments @((Join-Path $OutputDir "ob08_new_entries_dump.txt"))
    Invoke-CscriptFile -ScriptPath (Join-Path $scriptsDir "sap_gui_ob08_create_rates_ztw1.vbs") -Arguments @(
        $sapActionOut, $validFrom, $RateType, $usdRate, $eurRate, $jpyRate, $cnyRate
    )
}
else {
    Invoke-CscriptFile -ScriptPath (Join-Path $scriptsDir "sap_gui_ob08_update_existing_rates_ztw1.vbs") -Arguments @(
        $sapActionOut, $validFrom, $RateType, $usdRate, $eurRate, $jpyRate, $cnyRate
    )
}

$actionLines = Get-Content -LiteralPath $sapActionOut -Encoding UTF8
$saveLine = $actionLines | Where-Object { $_ -like "statusAfterSave=*" } | Select-Object -First 1
$sapSaveStatus = if ($saveLine) { ($saveLine -split "=", 2)[1].Trim() } else { "No SAP save status captured; review ob08_action.txt" }

Invoke-CscriptFile -ScriptPath (Join-Path $scriptsDir "sap_gui_go_tcode.vbs") -Arguments @("OB08", (Join-Path $OutputDir "ob08_nav_verify.txt"))
Invoke-CscriptFile -ScriptPath (Join-Path $scriptsDir "sap_gui_ob08_position_check_ztw1.vbs") -Arguments @($checkAfterOut, $validFrom, $RateType, ($currList -join ","))

$after = Parse-PositionCheck -Path $checkAfterOut
$verifyOk = $true
foreach ($curr in $currList) {
    $rows = @(Get-TargetRows -Parsed $after -Currency $curr -RateType $RateType -ValidFrom $validFrom -ToCurrency $ToCurrency)
    if ($rows.Count -ne 1) { $verifyOk = $false; break }
    $expected = Get-Rate $parsedRates $curr
    if (-not (Test-RateEqual -Actual $rows[0].KURSP -Expected $expected)) { $verifyOk = $false; break }
}
if (-not $verifyOk) {
    throw "SAP verification failed. Review $checkAfterOut."
}

$sapVerifyStatus = "Verified $RateType / USD|EUR|JPY|CNY / $ToCurrency / $validFrom and KURSP matches customs purchase rates."
$gmailStatus = "not sent"
$gmailMessageId = "not sent"

$notificationJson = & $pythonExe (Join-Path $scriptsDir "build_customs_notification.py") `
    --rates-json $parseOut `
    --out $resultFile `
    --rate-type $RateType `
    --to-currency $ToCurrency `
    --sap-save-status $sapSaveStatus `
    --sap-verify-status $sapVerifyStatus `
    --gmail-status $gmailStatus `
    --gmail-message-id $gmailMessageId
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build notification body."
}
$notification = $notificationJson | ConvertFrom-Json

if (-not $NoEmail) {
    $sendScript = Join-Path $gmailDir "send_gmail_report.py"
    Push-Location $gmailDir
    try {
        $subject = $notification.subject
        $sendJson = & $pythonExe $sendScript --to $Recipient --subject $subject --text-file $resultFile --json
        if ($LASTEXITCODE -ne 0) {
            throw "Gmail send failed: $sendJson"
        }
        $payload = $sendJson | ConvertFrom-Json
        if (-not $payload.ok) {
            throw "Gmail API failed: $sendJson"
        }
        $gmailStatus = "sent"
        $gmailMessageId = $payload.message_id
        & $pythonExe (Join-Path $scriptsDir "build_customs_notification.py") `
            --rates-json $parseOut `
            --out $resultFile `
            --rate-type $RateType `
            --to-currency $ToCurrency `
            --sap-save-status $sapSaveStatus `
            --sap-verify-status $sapVerifyStatus `
            --gmail-status $gmailStatus `
            --gmail-message-id $gmailMessageId | Out-Null
    }
    finally {
        Pop-Location
    }
}

Write-Host "Done. Result file: $resultFile"
