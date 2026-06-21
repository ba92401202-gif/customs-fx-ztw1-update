# 海關三旬買入匯率匯入 SAP ZTW1 Skill

這個 skill 用來把台灣海關 GC331「最新一旬匯率文字檔（Recent TEXT）」中的「買進」匯率，匯入 SAP `OB08` 的匯率類型 `ZTW1`。

公開版 repo 已移除個人化資訊，不包含個人 Email、OAuth 憑證、SAP 使用者、下載檔名、訊息 id、機器路徑與實際執行證據。

## 這個 Skill 做什麼

此流程固定處理以下四組幣別：

- `USD/TWD`
- `EUR/TWD`
- `JPY/TWD`
- `CNY/TWD`

資料來源固定為台灣海關 GC331 最新一旬文字檔，且只使用 `買進` 欄位。

SAP `Valid From` 日期依海關旬別決定：

- 第 1 旬：當月 `1` 日
- 第 2 旬：當月 `11` 日
- 第 3 旬：當月 `21` 日

## 流程說明

完整流程如下：

1. 開啟官方 GC331 頁面並下載 `下載最新一旬匯率文字檔（Recent TEXT）`。
2. 解析文字檔，只擷取 `USD`、`EUR`、`JPY`、`CNY` 的 `買進` 匯率。
3. 連到 SAP GUI `OB08`，先檢查 `ZTW1 / 幣別 / TWD / Valid From` 是否已存在。
4. 只有在以下兩種情況才會自動繼續：
   - 四筆都不存在：新增四筆
   - 四筆都存在：更新四筆
5. 若出現以下狀況，流程必須停止，不會假裝完成：
   - 只有部分幣別存在（mixed state）
   - 同一個 key 出現重複資料
   - SAP GUI 無法連線或儲存失敗
   - 驗證結果與海關買進匯率不一致
   - Gmail 發送失敗
6. SAP 儲存後重新進入 `OB08` 驗證四筆 `KURSP`，確認數值與海關買進匯率一致。
7. 成功時寄出繁體中文通知信；失敗時保留 output 證據供追查。

## 重要控制規則

- 只使用 GC331 文字檔的 `買進` 欄位。
- 不直接寫入 `FFACT` / `TFACT`，避免在不可編輯欄位上失敗。
- 驗證時用數值比較，例如 `31.51000` 與 `31.51` 視為相同。
- 若 `OB08` 是部分存在、部分不存在，必須先停下來處理，不能自動補半套。
- 每一步失敗都要保留輸出證據，不能回報成功。

## 安裝方式

把 repo clone 到 Codex skills 目錄：

```powershell
git clone https://github.com/ba92401202-gif/customs-fx-ztw1-update.git "$env:USERPROFILE\.codex\skills\customs-fx-ztw1-update"
```

如果要使用 Gmail API 發信，先安裝 Python 相依套件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\customs-fx-ztw1-update\runtime\install_dependencies.ps1"
```

如果要用本地 Gmail API 發信，請把 OAuth `credentials.json` 放到：

```text
%USERPROFILE%\.codex\skills\customs-fx-ztw1-update\runtime\gmail\credentials.json
```

## 使用前準備

執行前請先確認：

1. 已登入 SAP GUI，且該系統可使用 `OB08`。
2. SAP GUI scripting 已啟用。
3. 已從官方 GC331 頁面下載最新 `Recent TEXT`。
4. Windows 可執行 PowerShell、`cscript` 與 Python。
5. 若要寄信，已準備好 Gmail API 憑證；若沒有，也可選擇略過通知信。

## 執行方式

### 方式一：互動式執行

最簡單的方式是直接執行：

```powershell
%USERPROFILE%\.codex\skills\customs-fx-ztw1-update\runtime\run_now.cmd
```

互動流程會依序詢問：

- 是否寄送 Gmail 通知，以及收件人
- GC331 文字檔路徑，或是否自動從 Downloads 找最新檔案
- SAP GUI 是否已準備完成
- 匯率類型、目標幣別、來源幣別
- 寫入 SAP 前的最後確認

### 方式二：直接執行主腳本

若你已經有 GC331 文字檔，也可以直接呼叫主流程：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\customs-fx-ztw1-update\runtime\run_customs_fx_ztw1_update.ps1" -CustomsTextFile "C:\Path\to\GC331.tmp"
```

常用參數：

- `-Recipient`：通知收件人
- `-CustomsTextFile`：GC331 文字檔或 `.tmp` 檔
- `-RateType`：預設為 `ZTW1`
- `-ToCurrency`：預設為 `TWD`
- `-Currencies`：預設為 `USD,EUR,JPY,CNY`
- `-NoEmail`：只做 SAP 維護，不寄信

## 輸出結果與證據

流程執行後，會把輸出放在：

```text
%USERPROFILE%\.codex\skills\customs-fx-ztw1-update\runtime\output
```

常見輸出檔包含：

- `customs_gc331_latest.json`：解析後的海關匯率資料
- `sap_probe.txt`：SAP GUI 連線檢查結果
- `ob08_position_before.txt`：SAP 變更前檢查
- `ob08_target_counts_before.json`：四個 target key 的存在狀態
- `ob08_action.txt`：新增或更新時的 SAP 動作紀錄
- `ob08_position_after.txt`：儲存後驗證結果
- `customs_ztw1_update_YYYYMMDD.txt`：通知信本文與最終摘要

## 何時會停止

以下情況屬於正常停止，不應硬做：

- 找不到官方 GC331 文字檔
- GC331 檔案格式不符或解析失敗
- SAP GUI 未開啟或 scripting 不可用
- `OB08` 檢查結果為 mixed state
- `OB08` 有重複 key
- SAP 儲存成功但驗證值不一致
- Gmail 寄送失敗

這些情況都應保留 output 目錄中的證據檔，再由人員判斷後續處理。

## Repo 內容

- `README.md`：本說明文件
- `SKILL.md`：Codex skill 版工作流說明
- `runtime/`：可在 Windows 直接執行的 PowerShell、Python、VBS 腳本
- `references/mixed-state-recovery.md`：部分存在資料時的人工處理參考
- `agents/openai.yaml`：Codex UI metadata

## 適用情境

這個 repo 適合以下用途：

- 在另一台 Windows 電腦快速部署同一套海關匯率流程
- 由 Codex / automation 定期執行 GC331 → SAP `OB08` 更新
- 作為 SAP FI 顧問的可重用匯率維護工具包
