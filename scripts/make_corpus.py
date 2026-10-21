"""Deterministically generate a large mixed Chinese/English corpus for the search example.

Usage: python scripts/make_corpus.py <output dir> [--docs 2000] [--size 4096]
The text is synthetic (seeded vocabulary), so it carries no third-party content.
Prints the number of files, total bytes and a SHA256 over all files in name order.
"""
from pathlib import Path
import argparse
import hashlib
import random

ENGLISH = (
    "moonbit harmonyos native module arkts worker thread promise cancel token handle close "
    "rawfile resource manager hilog domain tag async task gate reference count memory index "
    "search ranking bm25 snippet document offline privacy device emulator archive har hvigor "
    "ohpm package build release verify checksum library interface declaration tokenizer query"
).split()
CHINESE = (
    "离线 检索 文档 索引 搜索 结果 设备 隐私 取消 任务 线程 句柄 释放 资源 日志 鸿蒙 模块 "
    "编译 打包 校验 接口 声明 分词 查询 排序 摘要 页面 界面 计算 内存 引用 生命周期 应用 帮助 手册"
).split()


def paragraph(rng: random.Random, words: int) -> str:
    out = []
    for _ in range(words):
        if rng.random() < 0.45:
            out.append(rng.choice(CHINESE))
        else:
            out.append(rng.choice(ENGLISH))
    return " ".join(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    parser.add_argument("--docs", type=int, default=2000)
    parser.add_argument("--size", type=int, default=4096)
    args = parser.parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    for old in output.glob("doc-*.md"):
        old.unlink()
    rng = random.Random(20261021)
    digest = hashlib.sha256()
    total = 0
    for index in range(args.docs):
        title = f"# 文档 {index:04d} {rng.choice(ENGLISH)} {rng.choice(CHINESE)}\n\n"
        body = []
        while sum(len(p.encode("utf-8")) for p in body) < args.size:
            body.append(paragraph(rng, rng.randint(20, 60)) + "\n\n")
        text = (title + "".join(body)).encode("utf-8")
        name = f"doc-{index:04d}.md"
        (output / name).write_bytes(text)
        digest.update(name.encode("utf-8") + b"\0" + text)
        total += len(text)
    print(f"CORPUS files={args.docs} bytes={total} sha256={digest.hexdigest()}")


if __name__ == "__main__":
    main()
