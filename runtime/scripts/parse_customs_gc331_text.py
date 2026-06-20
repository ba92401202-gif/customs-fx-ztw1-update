#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import json
from datetime import date
from decimal import Decimal
from pathlib import Path


TARGET_CURRENCIES = ("USD", "EUR", "JPY", "CNY")


def read_text(path: Path) -> str:
    data = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "cp950", "big5"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def period_start(year_roc: int, month: int, ten_day: int) -> date:
    year = year_roc + 1911
    if ten_day == 1:
        day = 1
    elif ten_day == 2:
        day = 11
    elif ten_day == 3:
        day = 21
    else:
        raise ValueError(f"Unsupported customs ten-day period: {ten_day}")
    return date(year, month, day)


def parse_file(path: Path, currencies: tuple[str, ...]) -> dict:
    text = read_text(path)
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if not parts or parts[0] == "幣別":
            continue
        if len(parts) < 6:
            continue
        rows.append(parts[:6])
    if not rows:
        raise ValueError("GC331 text file contains no data rows")

    normalized = {}
    for row in rows:
        curr = row[0].strip().upper()
        if not curr:
            continue
        normalized[curr] = {
            "currency": curr,
            "roc_year": int(row[1].strip()),
            "month": int(row[2].strip()),
            "ten_day": int(row[3].strip()),
            "purchase_in": str(Decimal(row[4].strip())),
            "sales_out": str(Decimal(row[5].strip())),
        }

    missing = [c for c in currencies if c not in normalized]
    if missing:
        raise ValueError(f"Missing required currencies in GC331 file: {', '.join(missing)}")

    sample = normalized[currencies[0]]
    valid_from = period_start(sample["roc_year"], sample["month"], sample["ten_day"])
    for curr in currencies[1:]:
        row = normalized[curr]
        row_start = period_start(row["roc_year"], row["month"], row["ten_day"])
        if row_start != valid_from:
            raise ValueError("Required currencies are not from the same customs period")

    return {
        "source_file": str(path),
        "source": "GC331 每旬報關適用外幣匯率文字檔",
        "valid_from": valid_from.strftime("%Y/%m/%d"),
        "period": {
            "roc_year": sample["roc_year"],
            "year": sample["roc_year"] + 1911,
            "month": sample["month"],
            "ten_day": sample["ten_day"],
        },
        "rates": {curr: normalized[curr] for curr in currencies},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse customs GC331 latest ten-day text rates.")
    parser.add_argument("path", type=Path)
    parser.add_argument("--currencies", default=",".join(TARGET_CURRENCIES))
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    currencies = tuple(c.strip().upper() for c in args.currencies.split(",") if c.strip())
    payload = parse_file(args.path, currencies)
    output = json.dumps(payload, ensure_ascii=False, indent=2)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(output, encoding="utf-8")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
