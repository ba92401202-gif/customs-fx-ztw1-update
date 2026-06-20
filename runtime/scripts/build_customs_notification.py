#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import json
from pathlib import Path


def build_body(data: dict, args: argparse.Namespace) -> str:
    period = data["period"]
    rates = data["rates"]
    rows = [
        "SAP 海關三旬買入匯率維護結果",
        "",
        "資料來源：GC331 每旬報關適用外幣匯率文字檔",
        f"來源檔案：{data['source_file']}",
        f"海關期間：民國 {period['roc_year']} 年 {period['month']:02d} 月第 {period['ten_day']} 旬",
        f"SAP Valid From：{data['valid_from']}",
        "",
        "SAP 交易碼：OB08",
        f"匯率類型：{args.rate_type}",
        f"目標幣別：{args.to_currency}",
        "使用欄位：買進匯率",
        "",
        "幣別 | 買進匯率 | SAP KURSP",
    ]
    for curr in ("USD", "EUR", "JPY", "CNY"):
        rows.append(f"{curr} | {rates[curr]['purchase_in']} | {rates[curr]['purchase_in']}")
    rows.extend(
        [
            "",
            f"SAP 儲存狀態：{args.sap_save_status}",
            f"SAP 驗證狀態：{args.sap_verify_status}",
            "",
            f"Gmail 寄送狀態：{args.gmail_status}",
            f"Gmail message id：{args.gmail_message_id}",
        ]
    )
    return "\n".join(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Traditional Chinese customs FX notification.")
    parser.add_argument("--rates-json", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--rate-type", default="ZTW1")
    parser.add_argument("--to-currency", default="TWD")
    parser.add_argument("--sap-save-status", default="")
    parser.add_argument("--sap-verify-status", default="")
    parser.add_argument("--gmail-status", default="未寄送")
    parser.add_argument("--gmail-message-id", default="未寄送")
    args = parser.parse_args()

    data = json.loads(args.rates_json.read_text(encoding="utf-8"))
    subject = f"SAP 海關三旬買入匯率維護通知 - {data['valid_from']} 已完成"
    body = build_body(data, args)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(body, encoding="utf-8")
    print(json.dumps({"subject": subject, "body_file": str(args.out)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
