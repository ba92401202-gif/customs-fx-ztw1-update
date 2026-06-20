#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
send_gmail_report.py — Gmail 統一發信包裝 v2.0
================================================

作者：Eric（SAP 自動化工作流專用）
向後相容：保留原 v1 的 --to / --subject / --html-file 介面
新增功能：--cc / --bcc / --attach / --text-file / --inline-image / --reply-to
         / --from-alias / --dry-run / --json / 自動 token 刷新 / 指數退避重試

# =============================================================================
# 安裝需求（首次設定）
# =============================================================================
#
# 1. 安裝套件：
#    py -3 -m pip install google-auth google-auth-oauthlib google-api-python-client
#
# 2. 準備 OAuth 憑證：
#    a) 到 Google Cloud Console 建立專案 → 啟用 Gmail API
#    b) 建立 OAuth 2.0 Client ID（類型：Desktop app）
#    c) 下載 credentials.json 放到本腳本同層目錄
#    d) 首次執行會跳出瀏覽器授權，同意後會自動產生 token.json
#
# 3. 必要 scope：https://www.googleapis.com/auth/gmail.send
#
# =============================================================================
# 使用範例
# =============================================================================
#
# 基本（相容 v1 呼叫方式）：
#   py -3 send_gmail_report.py ^
#       --to recipient@example.com ^
#       --subject "📈 盤前分析 20260424" ^
#       --html-file "C:\reports\premarket_20260424.html"
#
# 多收件人 + 附件：
#   py -3 send_gmail_report.py ^
#       --to "a@x.com,b@x.com" --cc "boss@x.com" ^
#       --subject "月結報告" ^
#       --html-file "C:\reports\monthly.html" ^
#       --attach "C:\reports\monthly.xlsx" ^
#       --attach "C:\reports\monthly.pdf"
#
# Cowork / 腳本呼叫（結構化輸出）：
#   py -3 send_gmail_report.py ... --json
#   → stdout 會輸出 {"ok": true, "message_id": "...", "thread_id": "..."}
#
# 測試不實際寄出：
#   py -3 send_gmail_report.py ... --dry-run
#
# =============================================================================
# Exit Codes
# =============================================================================
#   0 = 成功
#   1 = 參數或設定錯誤（credentials.json 缺失、檔案不存在等）
#   2 = Gmail API 錯誤（重試後仍失敗）
#   3 = 使用者授權錯誤（token 失效且無法刷新）
# =============================================================================
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import sys
import time
from email.message import EmailMessage
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# 常數設定
# ---------------------------------------------------------------------------
SCOPES = ["https://www.googleapis.com/auth/gmail.send"]
SCRIPT_DIR = Path(__file__).resolve().parent
CREDENTIALS_PATH = SCRIPT_DIR / "credentials.json"
TOKEN_PATH = SCRIPT_DIR / "token.json"

MAX_RETRIES = 3
RETRY_BACKOFF_BASE = 2  # 2, 4, 8 秒


# ---------------------------------------------------------------------------
# 輔助工具
# ---------------------------------------------------------------------------
def log(msg: str, *, quiet: bool = False, file=sys.stderr) -> None:
    """一般訊息輸出到 stderr，避免干擾 --json 模式的 stdout。"""
    if not quiet:
        print(f"[send_gmail_report] {msg}", file=file, flush=True)


def emit_json(payload: dict) -> None:
    """結構化輸出（供 Cowork / 其他腳本解析）。"""
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def die(exit_code: int, reason: str, *, json_mode: bool = False) -> None:
    """統一錯誤退出。"""
    if json_mode:
        emit_json({"ok": False, "exit_code": exit_code, "error": reason})
    else:
        log(f"ERROR: {reason}")
    sys.exit(exit_code)


def split_emails(value: Optional[str]) -> list[str]:
    """把 'a@x.com, b@x.com' 這種字串拆成 list，去空白與空項。"""
    if not value:
        return []
    return [e.strip() for e in value.split(",") if e.strip()]


def read_file_text(path: Path) -> str:
    """強制以 UTF-8 讀取文字檔，保留換行符。"""
    return path.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# OAuth / 憑證處理
# ---------------------------------------------------------------------------
def get_credentials():
    """
    取得有效的 Gmail API 憑證。
    - 沒有 token.json → 跳瀏覽器授權
    - token 過期但有 refresh_token → 自動刷新
    - refresh 失敗 → 刪除 token.json 重新授權
    """
    try:
        from google.auth.transport.requests import Request
        from google.oauth2.credentials import Credentials
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError as e:
        die(
            1,
            f"缺少 Google API 套件（{e.name}）。請執行："
            f"py -3 -m pip install google-auth google-auth-oauthlib google-api-python-client",
        )

    creds = None
    if TOKEN_PATH.exists():
        try:
            creds = Credentials.from_authorized_user_file(str(TOKEN_PATH), SCOPES)
        except Exception as e:
            log(f"token.json 讀取失敗，將重新授權：{e}")

    if creds and creds.valid:
        return creds

    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            TOKEN_PATH.write_text(creds.to_json(), encoding="utf-8")
            log("已自動刷新過期的 access token")
            return creds
        except Exception as e:
            log(f"token 刷新失敗，改走重新授權流程：{e}")
            try:
                TOKEN_PATH.unlink(missing_ok=True)
            except Exception:
                pass
            creds = None

    # 重新授權（需要有瀏覽器環境）
    if not CREDENTIALS_PATH.exists():
        die(
            1,
            f"找不到 credentials.json（預期路徑：{CREDENTIALS_PATH}）。"
            f"請到 Google Cloud Console 下載 OAuth Client 憑證。",
        )

    try:
        flow = InstalledAppFlow.from_client_secrets_file(str(CREDENTIALS_PATH), SCOPES)
        creds = flow.run_local_server(port=0)
        TOKEN_PATH.write_text(creds.to_json(), encoding="utf-8")
        log("首次授權完成，token.json 已儲存")
        return creds
    except Exception as e:
        die(3, f"OAuth 授權流程失敗：{e}")


# ---------------------------------------------------------------------------
# 郵件組裝
# ---------------------------------------------------------------------------
def build_message(args) -> EmailMessage:
    """根據 CLI 參數組出完整 MIME 郵件。"""
    msg = EmailMessage()
    msg["To"] = ", ".join(split_emails(args.to))

    if args.cc:
        msg["Cc"] = ", ".join(split_emails(args.cc))
    if args.bcc:
        msg["Bcc"] = ", ".join(split_emails(args.bcc))
    if args.reply_to:
        msg["Reply-To"] = args.reply_to
    if args.from_alias:
        msg["From"] = args.from_alias

    msg["Subject"] = args.subject

    # --- 內文：text 與 html 兩種都可獨立存在或並存 ---
    text_body: Optional[str] = None
    html_body: Optional[str] = None

    if args.text_file:
        text_body = read_file_text(Path(args.text_file))
    if args.html_file:
        html_body = read_file_text(Path(args.html_file))
    if args.text and not text_body:
        text_body = args.text
    if args.html and not html_body:
        html_body = args.html

    # 至少要有一個內文
    if not text_body and not html_body:
        raise ValueError(
            "必須提供下列其中之一：--html-file / --text-file / --html / --text"
        )

    # 如果只有 HTML，自動產生 plain text fallback（簡易去 tag）
    if html_body and not text_body:
        import re
        text_body = re.sub(r"<[^>]+>", "", html_body)
        text_body = re.sub(r"\n\s*\n", "\n\n", text_body).strip()

    # set_content 會設定 text/plain；add_alternative 加上 text/html
    msg.set_content(text_body or "")
    if html_body:
        msg.add_alternative(html_body, subtype="html")

    # --- Inline images：--inline-image cid=path ---
    if args.inline_image:
        for entry in args.inline_image:
            if "=" not in entry:
                raise ValueError(f"--inline-image 格式錯誤（需 cid=path）：{entry}")
            cid, img_path = entry.split("=", 1)
            img_path = Path(img_path)
            if not img_path.exists():
                raise FileNotFoundError(f"inline image 檔案不存在：{img_path}")
            mime_type, _ = mimetypes.guess_type(str(img_path))
            if not mime_type or not mime_type.startswith("image/"):
                mime_type = "image/png"
            maintype, subtype = mime_type.split("/", 1)
            # 加到 html 那個 alternative part
            html_part = msg.get_payload()[-1]
            html_part.add_related(
                img_path.read_bytes(),
                maintype=maintype,
                subtype=subtype,
                cid=f"<{cid}>",
                filename=img_path.name,
            )

    # --- 附件：--attach 可重複 ---
    if args.attach:
        for att in args.attach:
            att_path = Path(att)
            if not att_path.exists():
                raise FileNotFoundError(f"附件不存在：{att_path}")
            mime_type, _ = mimetypes.guess_type(str(att_path))
            if not mime_type:
                mime_type = "application/octet-stream"
            maintype, subtype = mime_type.split("/", 1)
            msg.add_attachment(
                att_path.read_bytes(),
                maintype=maintype,
                subtype=subtype,
                filename=att_path.name,
            )

    return msg


# ---------------------------------------------------------------------------
# 傳送（含重試）
# ---------------------------------------------------------------------------
def send_with_retry(service, raw_message: dict, *, quiet: bool = False) -> dict:
    """Gmail API 呼叫 + 指數退避重試（處理 429 / 5xx）。"""
    try:
        from googleapiclient.errors import HttpError
    except ImportError:
        die(1, "缺少 googleapiclient，請 pip install google-api-python-client")

    last_err: Optional[Exception] = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            result = (
                service.users()
                .messages()
                .send(userId="me", body=raw_message)
                .execute()
            )
            return result
        except HttpError as e:
            status = getattr(e.resp, "status", 0)
            last_err = e
            if status in (429, 500, 502, 503, 504) and attempt < MAX_RETRIES:
                wait = RETRY_BACKOFF_BASE ** attempt
                log(f"Gmail API 回傳 {status}，{wait} 秒後重試（{attempt}/{MAX_RETRIES}）", quiet=quiet)
                time.sleep(wait)
                continue
            raise
        except Exception as e:
            last_err = e
            raise

    if last_err:
        raise last_err
    raise RuntimeError("send_with_retry 邏輯錯誤：未收到結果也無例外")


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Gmail 統一發信包裝腳本（v2）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # --- 核心（v1 相容） ---
    p.add_argument("--to", required=True, help="收件人（逗號分隔多個）")
    p.add_argument("--subject", required=True, help="主旨（支援中文/emoji）")
    p.add_argument("--html-file", help="HTML 內文檔案路徑")

    # --- 新增：更多內文來源 ---
    p.add_argument("--text-file", help="純文字內文檔案路徑")
    p.add_argument("--html", help="直接指定 HTML 字串（小量內容用）")
    p.add_argument("--text", help="直接指定純文字字串")

    # --- 新增：其他收件人欄位 ---
    p.add_argument("--cc", help="副本（逗號分隔）")
    p.add_argument("--bcc", help="密件副本（逗號分隔）")
    p.add_argument("--reply-to", help="Reply-To 信箱")
    p.add_argument("--from-alias", help="寄件人顯示（需是 Gmail 已驗證的 send-as alias）")

    # --- 新增：附件與嵌入圖 ---
    p.add_argument("--attach", action="append", help="附件路徑（可重複）")
    p.add_argument(
        "--inline-image",
        action="append",
        help="嵌入圖 cid=path（在 HTML 中以 <img src='cid:xxx'> 引用）",
    )

    # --- 執行控制 ---
    p.add_argument("--dry-run", action="store_true", help="只組訊息不實際寄出")
    p.add_argument("--json", action="store_true", help="輸出 JSON 結果到 stdout")
    p.add_argument("--quiet", action="store_true", help="不印 info 訊息")

    return p.parse_args()


def main() -> int:
    args = parse_args()
    json_mode = args.json

    # --- 基本檢查 ---
    if not split_emails(args.to):
        die(1, "--to 至少要有一個有效的 email", json_mode=json_mode)

    if args.html_file and not Path(args.html_file).exists():
        die(1, f"--html-file 不存在：{args.html_file}", json_mode=json_mode)

    if args.text_file and not Path(args.text_file).exists():
        die(1, f"--text-file 不存在：{args.text_file}", json_mode=json_mode)

    # --- 組訊息 ---
    try:
        msg = build_message(args)
    except (ValueError, FileNotFoundError) as e:
        die(1, str(e), json_mode=json_mode)

    raw_b64 = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    raw_message = {"raw": raw_b64}

    # --- Dry run ---
    if args.dry_run:
        info = {
            "ok": True,
            "dry_run": True,
            "to": msg["To"],
            "cc": msg["Cc"],
            "bcc": msg["Bcc"],
            "subject": msg["Subject"],
            "size_bytes": len(msg.as_bytes()),
            "attachments": len(args.attach or []),
        }
        if json_mode:
            emit_json(info)
        else:
            log(f"Dry run OK：{info}", quiet=args.quiet)
        return 0

    # --- 真的寄送 ---
    try:
        from googleapiclient.discovery import build
    except ImportError:
        die(1, "缺少 googleapiclient，請 pip install google-api-python-client",
            json_mode=json_mode)

    creds = get_credentials()
    service = build("gmail", "v1", credentials=creds, cache_discovery=False)

    try:
        result = send_with_retry(service, raw_message, quiet=args.quiet)
    except Exception as e:
        die(2, f"Gmail API 寄送失敗：{e}", json_mode=json_mode)
        return 2  # 讓 type checker 開心

    payload = {
        "ok": True,
        "message_id": result.get("id"),
        "thread_id": result.get("threadId"),
        "label_ids": result.get("labelIds", []),
        "to": msg["To"],
        "subject": msg["Subject"],
    }
    if json_mode:
        emit_json(payload)
    else:
        log(f"已寄出 → id={payload['message_id']}", quiet=args.quiet)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        log("使用者中斷")
        sys.exit(130)
