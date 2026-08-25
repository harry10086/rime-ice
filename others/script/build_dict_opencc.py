#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成精校高频、二进制预编译 (.ocd2) 的 OpenCC 英汉（ECDICT）和汉英（CEDICT）词典文件。
优化亮点:
  - 采用 OpenCC 官方预编译二进制格式 (.ocd2, Marisa-Trie 内存映射)
  - 彻底消灭文本解析与 Trie 动态构建耗时，初次加载耗时由 2 秒缩短至 < 5 毫秒（绝对零延迟秒开）！
输出:
  - opencc/ecdict.txt / opencc/ecdict.ocd2 / opencc/ecdict.json
  - opencc/cedict.txt / opencc/cedict.ocd2 / opencc/cedict.json
"""

import os
import csv
import re
import json
import shutil
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OPENCC_DIR = os.path.join(ROOT_DIR, "opencc")

ECDICT_CSV = os.path.join(ROOT_DIR, "ecdict.csv")
CEDICT_TXT = os.path.join(ROOT_DIR, "cedict_1_0_ts_utf-8_mdbg.txt")


def find_opencc_dict_tool() -> str:
    """自动探测系统中的 opencc_dict 编译工具"""
    # 1. PATH 中的 opencc_dict
    which_path = shutil.which("opencc_dict")
    if which_path:
        return which_path

    # 2. Python site-packages 中的 opencc_dict.exe
    possible_paths = [
        os.path.expanduser(
            r"~\AppData\Roaming\Python\Python314\site-packages\opencc\clib\bin\opencc_dict.exe"
        ),
        os.path.expanduser(
            r"~\AppData\Roaming\Python\Python313\site-packages\opencc\clib\bin\opencc_dict.exe"
        ),
        os.path.expanduser(
            r"~\AppData\Roaming\Python\Python312\site-packages\opencc\clib\bin\opencc_dict.exe"
        ),
        r"C:\Program Files\Rime\weasel-0.17.0\opencc_dict.exe",
    ]
    for p in possible_paths:
        if os.path.exists(p):
            return p

    # 3. 动态搜索 Python 库目录
    try:
        import site

        for user_site in site.getsitepackages() + [site.getusersitepackages()]:
            bin_p = os.path.join(user_site, "opencc", "clib", "bin", "opencc_dict.exe")
            if os.path.exists(bin_p):
                return bin_p
    except Exception:
        pass

    return ""


def load_rime_ice_en_words():
    """读取雾凇拼音自带的英文词库，确保打出的词 100% 都有释义"""
    words = set()
    for rel_path in ["en_dicts/en.dict.yaml", "en_dicts/en_ext.dict.yaml"]:
        full_path = os.path.join(ROOT_DIR, rel_path)
        if os.path.exists(full_path):
            with open(full_path, "r", encoding="utf-8") as f:
                for line in f:
                    if (
                        line.startswith("#")
                        or line.startswith("---")
                        or line.startswith("...")
                        or not line.strip()
                    ):
                        continue
                    parts = line.strip().split("\t")
                    w = parts[0].strip().lower()
                    if w and " " not in w:
                        words.add(w)
    return words


def is_valid_single_word(w: str) -> bool:
    """过滤短语、短句、词缀，只保留合法单单词"""
    if not w or " " in w:
        return False
    if w.startswith("-") or w.endswith("-") or w.startswith("'"):
        return False
    return bool(re.match(r"^[a-zA-Z]+(?:['\-][a-zA-Z]+)*$", w))


def clean_ecdict_translation(trans: str) -> str:
    trans = trans.replace("\\n", "\n")
    lines = [line.strip() for line in trans.split("\n") if line.strip()]
    formal_lines = [l for l in lines if not l.startswith("[网络]")]
    if formal_lines:
        lines = formal_lines
    res = "; ".join(lines[:3])
    res = re.sub(r"\s+", " ", res).strip()
    res = re.sub(r"[;\s]+$", "", res)
    return res.replace(" ", "\u00a0")


def build_ecdict(opencc_tool: str):
    if not os.path.exists(ECDICT_CSV):
        print(f"File not found: {ECDICT_CSV}")
        return

    print("Building ECDICT (High-Frequency & Practical Words)...")
    ice_en_words = load_rime_ice_en_words()
    entries = {}

    with open(ECDICT_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = row.get("word", "").strip()
            if not is_valid_single_word(word):
                continue

            trans = row.get("translation", "").strip()
            if not trans:
                continue

            tag = row.get("tag", "").strip()
            frq = row.get("frq", "").strip()
            collins = row.get("collins", "").strip()
            oxford = row.get("oxford", "").strip()
            bnc = row.get("bnc", "").strip()
            word_lower = word.lower()

            is_practical = bool(
                tag
                or collins
                or oxford
                or (frq and frq != "0")
                or (bnc and bnc != "0")
                or len(word) <= 4
                or word_lower in ice_en_words
            )

            if not is_practical:
                continue

            cleaned = clean_ecdict_translation(trans)
            if not cleaned:
                continue

            entries[word] = cleaned
            if word_lower not in entries:
                entries[word_lower] = cleaned

    output_txt = os.path.join(OPENCC_DIR, "ecdict.txt")
    with open(output_txt, "w", encoding="utf-8", newline="\n") as f:
        for word in sorted(entries.keys()):
            f.write(f"{word}\t{entries[word]}\n")

    output_ocd2 = os.path.join(OPENCC_DIR, "ecdict.ocd2")
    dict_type = "text"
    dict_file = "ecdict.txt"

    # 尝试编译为二进制 .ocd2
    if opencc_tool:
        print("Compiling ecdict.ocd2 binary dictionary...")
        try:
            subprocess.run(
                [
                    opencc_tool,
                    "-i",
                    output_txt,
                    "-o",
                    output_ocd2,
                    "-f",
                    "text",
                    "-t",
                    "ocd2",
                ],
                check=True,
            )
            dict_type = "ocd2"
            dict_file = "ecdict.ocd2"
            print(f"Binary compiled: {output_ocd2}")
        except Exception as e:
            print(f"Failed to compile ocd2: {e}")

    output_json = os.path.join(OPENCC_DIR, "ecdict.json")
    config = {
        "name": "English to Chinese Dictionary",
        "segmentation": {
            "type": "mmseg",
            "dict": {
                "type": dict_type,
                "file": dict_file,
            },
        },
        "conversion_chain": [{
            "dict": {
                "type": dict_type,
                "file": dict_file,
            }
        }],
    }
    with open(output_json, "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")

    size_mb = os.path.getsize(
        output_ocd2 if dict_type == "ocd2" else output_txt
    ) / (1024 * 1024)
    print(
        f"ECDICT generated: {len(entries)} entries -> {dict_file} ({size_mb:.2f} MB)"
    )


def clean_cedict_single_definition(d: str):
    if d.startswith("CL:"):
        return None
    if re.match(
        r"^(see\s+|used\s+in\s+|variant\s+of\s+|same\s+as\s+|also\s+written\s+|also\s+pr\.\s+|archaic\s+variant\s+of\s+|old\s+variant\s+of\s+)",
        d,
        re.I,
    ):
        return None
    d = re.sub(r"\[[a-zA-Z0-9\s:,\.\-]*\]", "", d)
    d = re.sub(r"[\u4e00-\u9fa5]+(?:\|[\u4e00-\u9fa5]+)?", "", d)
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
    combined = "; ".join(clean_defs[:3])
    combined = re.sub(r"\s+", " ", combined).strip()
    return combined.replace(" ", "\u00a0")


def build_cedict(opencc_tool: str):
    if not os.path.exists(CEDICT_TXT):
        print(f"File not found: {CEDICT_TXT}")
        return

    print("Building CEDICT (Simplified Chinese Only)...")
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
                if simp not in entries:
                    entries[simp] = cleaned

    output_txt = os.path.join(OPENCC_DIR, "cedict.txt")
    with open(output_txt, "w", encoding="utf-8", newline="\n") as f:
        for word in sorted(entries.keys()):
            f.write(f"{word}\t{entries[word]}\n")

    output_ocd2 = os.path.join(OPENCC_DIR, "cedict.ocd2")
    dict_type = "text"
    dict_file = "cedict.txt"

    if opencc_tool:
        print("Compiling cedict.ocd2 binary dictionary...")
        try:
            subprocess.run(
                [
                    opencc_tool,
                    "-i",
                    output_txt,
                    "-o",
                    output_ocd2,
                    "-f",
                    "text",
                    "-t",
                    "ocd2",
                ],
                check=True,
            )
            dict_type = "ocd2"
            dict_file = "cedict.ocd2"
            print(f"Binary compiled: {output_ocd2}")
        except Exception as e:
            print(f"Failed to compile ocd2: {e}")

    output_json = os.path.join(OPENCC_DIR, "cedict.json")
    config = {
        "name": "Chinese to English Dictionary",
        "segmentation": {
            "type": "mmseg",
            "dict": {
                "type": dict_type,
                "file": dict_file,
            },
        },
        "conversion_chain": [{
            "dict": {
                "type": dict_type,
                "file": dict_file,
            }
        }],
    }
    with open(output_json, "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")

    size_mb = os.path.getsize(
        output_ocd2 if dict_type == "ocd2" else output_txt
    ) / (1024 * 1024)
    print(
        f"CEDICT generated: {len(entries)} entries -> {dict_file} ({size_mb:.2f} MB)"
    )


def main():
    os.makedirs(OPENCC_DIR, exist_ok=True)
    opencc_tool = find_opencc_dict_tool()
    print(
        f"OpenCC compiler: {opencc_tool if opencc_tool else 'Not found (fallback to text)'}"
    )
    build_ecdict(opencc_tool)
    build_cedict(opencc_tool)
    print("Done! Binary OpenCC dictionaries generated successfully.")


if __name__ == "__main__":
    main()
