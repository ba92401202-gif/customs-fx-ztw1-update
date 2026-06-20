# Customs FX ZTW1 Update Skill

Codex skill and portable Windows runtime for importing Taiwan Customs GC331 ten-day purchase rates into SAP OB08 exchange-rate type `ZTW1`.

This public export is sanitized. It does not include personal email addresses, OAuth credentials, local download filenames, SAP user names, message ids, or machine-specific workflow output.

## Install On Another Computer

Clone this repo into the Codex skills folder:

```powershell
git clone https://github.com/ba92401202-gif/customs-fx-ztw1-update.git "$env:USERPROFILE\.codex\skills\customs-fx-ztw1-update"
```

Install Python dependencies once if Gmail sending is needed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\customs-fx-ztw1-update\runtime\install_dependencies.ps1"
```

For Gmail API sending, place OAuth `credentials.json` here before the first run:

```text
%USERPROFILE%\.codex\skills\customs-fx-ztw1-update\runtime\gmail\credentials.json
```

## Run

1. Open SAP GUI and log in to a system where `OB08` is available and SAP GUI scripting is enabled.
2. Open the official GC331 page and download `下載最新一旬匯率文字檔(Recent TEXT)`.
3. Run:

```powershell
%USERPROFILE%\.codex\skills\customs-fx-ztw1-update\runtime\run_now.cmd
```

The interactive runner asks for:

- Recipient email, or whether to skip Gmail.
- GC331 text file path, or confirmation to auto-detect the newest GC331-like file in Downloads.
- SAP GUI readiness.
- Rate type, target currency, and source currencies.
- Final confirmation before SAP changes are executed.

## Contents

- `SKILL.md`: core workflow and rules.
- `runtime/`: portable PowerShell, Python, and SAP GUI scripting runtime.
- `references/mixed-state-recovery.md`: manual recovery pattern for partial OB08 key states.
- `agents/openai.yaml`: Codex UI metadata.
