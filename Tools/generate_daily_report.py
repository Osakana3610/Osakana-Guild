#!/usr/bin/env python3
import subprocess, os
from datetime import datetime, timedelta, timezone
from collections import OrderedDict

JST = timezone(timedelta(hours=9))

def window_key(ts_iso: str) -> str:
    dt = datetime.fromisoformat(ts_iso)
    j = dt.astimezone(JST)
    # Day window boundary at 08:00 JST
    if j.hour < 8:
        j = j - timedelta(days=1)
    return f"{j.year}/{j.month}/{j.day}"

ERR_WORDS_JA = ['ビルドエラー','コンパイルエラー','ビルド失敗','ビルド修正']
ERR_WORDS_EN = ['build error','build errors','fix build','compile error','build failed','build fail','compile fix']

def is_build_fix(subj: str) -> bool:
    s = subj.lower()
    if any(w in subj for w in ERR_WORDS_JA):
        return True
    return any(w in s for w in ERR_WORDS_EN)

def normalize_subject(s: str) -> str:
    return s.replace('\\n', '\n').strip()

def format_block(subj: str) -> list[str]:
    s = normalize_subject(subj)
    lines = s.splitlines()
    if not lines:
        return []
    head = lines[0].strip()
    parts = head.split(' - ')
    out: list[str] = []
    if len(parts) == 1:
        out.append(head)
    else:
        head0 = parts[0].rstrip(':') + ':'
        out.append(head0)
        for p in parts[1:]:
            out.append(' - ' + p.strip())
    for extra in lines[1:]:
        extra = extra.strip()
        if not extra:
            continue
        if extra.startswith('- '):
            out.append(' - ' + extra[2:].strip())
        elif extra.startswith('-'):
            out.append(' - ' + extra[1:].strip())
        else:
            out.append(extra)
    return out

def main() -> int:
    out = subprocess.check_output(['git','log','--pretty=format:%H|%cI|%s'], text=True)
    by_day: dict[str, list[str]] = OrderedDict()
    for line in out.splitlines():
        try:
            _h, ts, subj = line.split('|', 2)
        except ValueError:
            continue
        subj = subj.strip()
        if subj.startswith('Merge '):
            continue
        if is_build_fix(subj):
            continue
        key = window_key(ts)
        by_day.setdefault(key, []).append(subj)

    os.makedirs('Documents/Working', exist_ok=True)
    path = 'Documents/Working/日報.md'
    with open(path, 'w', encoding='utf-8') as f:
        for day, subjects in by_day.items():
            f.write(f"{day}\n")
            seen = set()
            for subj in subjects:
                if subj in seen:
                    continue
                seen.add(subj)
                for line in format_block(subj):
                    f.write(line + '\n')
            f.write('\n')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
