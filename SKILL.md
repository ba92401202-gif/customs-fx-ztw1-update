---
name: customs-fx-ztw1-update
description: Run a Taiwan Customs GC331 Recent TEXT to SAP OB08 exchange-rate workflow for rate type ZTW1. Use when the user asks to import customs ten-day purchase rates, GC331 customs purchase rates, or maintain SAP ZTW1 USD/EUR/JPY/CNY to local-currency rates with completion notice.
---

# Customs FX ZTW1 Update

## Workflow

Use this skill for a recurring customs exchange-rate workflow:

1. Read the automation or run memory first when available.
2. Open the official GC331 page: `https://portal.sw.nat.gov.tw/APGQ/XGC331`.
3. Download `下載最新一旬匯率文字檔(Recent TEXT)`. A browser `.tmp` download is valid if its content is the GC331 text table.
4. Parse only the `買進` column for `USD`, `EUR`, `JPY`, and `CNY`.
5. Derive SAP Valid From from the GC331 ten-day period: ten-day 1 = day 1, ten-day 2 = day 11, ten-day 3 = day 21.
6. Maintain SAP GUI `OB08`, rate type `ZTW1`, pairs `USD/TWD`, `EUR/TWD`, `JPY/TWD`, and `CNY/TWD` unless the local implementation parameterizes target currency.
7. Before changing SAP, position-check each target key: `ZTW1 / from-currency / target-currency / Valid From`.
8. Continue automatically only when all target keys are missing or all target keys exist.
9. Stop and report when the target state is mixed or duplicate. Do not silently add missing rows unless the user explicitly authorizes that repair.
10. After saving, re-enter `OB08` and verify all target `KURSP` values numerically match GC331 purchase rates.
11. Send a Traditional Chinese completion notice. Include source period, rates, SAP save/verify status, and mail message id.

## Portable Runtime

This repo includes a Windows runtime under `runtime/`.

Install dependencies for Gmail sending:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\runtime\install_dependencies.ps1"
```

Run interactively:

```powershell
.\runtime\run_now.cmd
```

The interactive runner must ask for required runtime information before changing SAP:

- Recipient email or skip Gmail.
- GC331 text file path, or confirmation that the newest GC331-like file is in Downloads.
- SAP GUI login/readiness confirmation.
- Rate type, target currency, and source currencies.
- Final confirmation before SAP update.

## SAP Rules

- Do not directly write `FFACT` or `TFACT` in OB08. In some SAP GUI layouts those controls display ratio values but are not changeable. Let SAP default or carry ratio values after entering the currency pair and rate.
- Treat display padding as equal by decimal comparison, for example `31.51000` equals `31.51`, and `0.19520` equals `0.1952`.
- Parse OB08 dump rows with `yyyy/MM/dd` as a single `Valid From` field; do not split rows by `/` naively.
- In PowerShell, wrap single-row function results in `@(...)` before calling `.Count`; otherwise one existing row can be misread.
- Preserve output evidence for every stop. Never claim SAP or mail completion if any step failed.

## Mixed-State Repair

If precheck reports a mixed state, stop first. Example:

```text
USD=1, EUR=1, JPY=0, CNY=0
```

Only after explicit user authorization, add the missing currencies without changing existing ones. See `references/mixed-state-recovery.md` for the recovery pattern.

After any manual repair, always rerun OB08 position-check for all target currencies and send the final completion notice with the actual message id.

## Mail Fallback

If the local Gmail or mail script is blocked by missing OAuth credentials or runtime dependencies, use an approved connector or organization mail mechanism to send the same notification body. Then rebuild or update the output notice file so it includes the actual sent status and message id.
