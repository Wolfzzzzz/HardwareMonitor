#!/usr/bin/env python3
"""HardwareMonitor Pro 激活码生成器（开发者专用）
用法: python3 make_license.py [数量]
输出: 每行一个激活码，格式 XXXX-XXXX-XXXX-XXXX-XXXXX-X
校验算法与 App 内 License.swift 一致（DJB2 hash mod 32）
"""
import random
import sys

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def checksum(data: str) -> str:
    h = 5381
    for ch in data:
        h = (h * 33 + ALPHABET.index(ch)) % (2**64)
    return ALPHABET[h % 32]


def generate() -> str:
    data = "".join(random.choice(ALPHABET) for _ in range(21))
    code = data + checksum(data)
    parts = [code[:4], code[4:8], code[8:12], code[12:16], code[16:21], code[21:22]]
    return "-".join(parts)


def validate(code: str) -> bool:
    s = code.replace("-", "").upper()
    if len(s) != 22 or any(c not in ALPHABET for c in s):
        return False
    return checksum(s[:21]) == s[21]


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    for _ in range(n):
        code = generate()
        assert validate(code), "自检失败"
        print(code)
    print(f"\n自检通过：生成 {n} 枚激活码", file=sys.stderr)
