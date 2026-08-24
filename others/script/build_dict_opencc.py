#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成精简后的 OpenCC 格式英汉（ECDICT）和汉英（CEDICT）词典文件。
规则:
  - 英汉词典（ECDICT）：仅保留纯英文单单词，过滤所有多词短语、短句、词缀与无意义符号。
  - 汉英词典（CEDICT）：仅保留简体中文条目，彻底剔除繁体字及其释义；过滤纯参见指引词条。
输出:
  - opencc/ecdict.txt
  - opencc/ecdict.json
  - opencc/cedict.txt
  - opencc/cedict.json
"""

import os
import csv
import re
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OPENCC_DIR = os.path.join(ROOT_DIR, "opencc")

ECDICT_CSV = os.path.join(ROOT_DIR, "ecdict.csv")
CEDICT_TXT = os.path.join(ROOT_DIR, "cedict_1_0_ts_utf-8_mdbg.txt")


def is_valid_single_word(w: str) -> bool:
    """仅保留纯英文单词（允许内部连字符或撇号，如 o'clock, user-friendly，但禁止空格短语及前后词缀符号）"""
    if not w or " " in w:
        return False
    # 过滤前缀后缀如 -able, -tion, 'hood
    if w.startswith("-") or w.endswith("-") or w.startswith("'"):
        return False
    return bool(re.match(r"^[a-zA-Z]+(?:['\-][a-zA-Z]+)*$", w))


def clean_ecdict_translation(trans: str) -> str:
    trans = trans.replace("\\n", "\n")
    lines = [line.strip() for line in trans.split("\n") if line.strip()]
    formal_lines = [l for l in lines if not l.startswith("[网络]")]
    if formal_lines:
        lines = formal_lines
    res = "; ".join(lines)
    res = re.sub(r"\s+", " ", res).strip()
    res = re.sub(r"[;\s]+$", "", res)
    # 将内部空格替换为不换行空格 \u00a0，以避免 OpenCC 按空格切分为多候选
    res = res.replace(" ", "\u00a0")
    return res


def build_ecdict():
    if not os.path.exists(ECDICT_CSV):
        print(f"File not found: {ECDICT_CSV}")
        return

    print("Building ECDICT (Single Words Only, English -> Chinese)...")
    entries = {}
    with open(ECDICT_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = row.get("word", "").strip()
            # 过滤短语、短句、非单词
            if not is_valid_single_word(word):
                continue

            trans = row.get("translation", "").strip()
            if not trans:
                continue

            cleaned = clean_ecdict_translation(trans)
            if not cleaned:
                continue

            entries[word] = cleaned
            word_lower = word.lower()
            if word_lower not in entries:
                entries[word_lower] = cleaned

    output_txt = os.path.join(OPENCC_DIR, "ecdict.txt")
    with open(output_txt, "w", encoding="utf-8", newline="\n") as f:
        for word in sorted(entries.keys()):
            f.write(f"{word}\t{entries[word]}\n")

    output_json = os.path.join(OPENCC_DIR, "ecdict.json")
    config = {
        "name": "English to Chinese Dictionary",
        "segmentation": {
            "type": "mmseg",
            "dict": {
                "type": "text",
                "file": "ecdict.txt"
            }
        },
        "conversion_chain": [{
            "dict": {
                "type": "text",
                "file": "ecdict.txt"
            }
        }]
    }
    with open(output_json, "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"ECDICT generated: {len(entries)} entries -> {output_txt}")


def clean_cedict_single_definition(d: str):
    """清洗单条 CEDICT 释义，去除无意义交叉索引、中文及注音"""
    if d.startswith("CL:"):
        return None
    # 过滤纯交叉引用/变体指示/参见指引
    if re.match(r"^(see\s+|used\s+in\s+|variant\s+of\s+|same\s+as\s+|also\s+written\s+|also\s+pr\.\s+|archaic\s+variant\s+of\s+|old\s+variant\s+of\s+)", d, re.I):
        return None
    # 清理拼音方括号 [shang3 sheng1]
    d = re.sub(r"\[[a-zA-Z0-9\s:,\.\-]*\]", "", d)
    # 清理中文文字与繁简竖线标注（如 上聲|上声）
    d = re.sub(r"[\u4e00-\u9fa5]+(?:\|[\u4e00-\u9fa5]+)?", "", d)
    # 清理多余符号与首尾空白
    d = re.sub(r"\s+", " ", d).strip(" ;:,/-|")
    return d if d else None


def clean_cedict_definitions(defs_str: str) -> str:
    raw_defs = [d.strip() for d in defs_str.split("/") if d.strip()]
    clean_defs = []
    for d in raw_defs:
        c = clean_cedict_single_definition(d)
        if c and c not in clean_defs:
            clean_defs.append(c)
    if not clean_defs:
        return ""
    combined = "; ".join(clean_defs)
    combined = re.sub(r"\s+", " ", combined).strip()
    combined = combined.replace(" ", "\u00a0")
    return combined


def build_cedict():
    if not os.path.exists(CEDICT_TXT):
        print(f"File not found: {CEDICT_TXT}")
        return

    print("Building CEDICT (Simplified Chinese Only, Chinese -> English)...")
    entries = {}
    with open(CEDICT_TXT, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^(\S+)\s+(\S+)\s+\[(.*?)\]\s+/(.+)/$", line)
            if m:
                trad, simp, pinyin, defs = m.groups()
                cleaned = clean_cedict_definitions(defs)
                if not cleaned:
                    continue

                # 仅保留简体中文 simp，彻底剔除繁体 trad
                if simp not in entries:
                    entries[simp] = cleaned

    output_txt = os.path.join(OPENCC_DIR, "cedict.txt")
    with open(output_txt, "w", encoding="utf-8", newline="\n") as f:
        for word in sorted(entries.keys()):
            f.write(f"{word}\t{entries[word]}\n")

    output_json = os.path.join(OPENCC_DIR, "cedict.json")
    config = {
        "name": "Chinese to English Dictionary",
        "segmentation": {
            "type": "mmseg",
            "dict": {
                "type": "text",
                "file": "cedict.txt"
            }
        },
        "conversion_chain": [{
            "dict": {
                "type": "text",
                "file": "cedict.txt"
            }
        }]
    }
    with open(output_json, "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"CEDICT generated: {len(entries)} entries -> {output_txt}")


def main():
    os.makedirs(OPENCC_DIR, exist_ok=True)
    build_ecdict()
    build_cedict()
    print("Done!")


if __name__ == "__main__":
    main()
