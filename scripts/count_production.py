"""Count tracked, formatted MoonBit source, excluding comments and templates."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {"examples", "fixtures", "tests", "third_party", "vendor", "generated", ".mooncakes", "_build"}

def code_lines(text):
    block_depth = 0
    count = 0
    for line in text.splitlines():
        if line.lstrip().startswith(("#|", "$|")) and block_depth == 0:
            continue
        cursor = 0
        tokens = []
        while cursor < len(line):
            pair = line[cursor:cursor+2]
            if block_depth:
                if pair == "/*":
                    block_depth += 1
                    cursor += 2
                elif pair == "*/":
                    block_depth -= 1
                    cursor += 2
                else:
                    cursor += 1
                continue
            if pair == "//":
                break
            if pair == "/*":
                block_depth = 1
                cursor += 2
                continue
            char = line[cursor]
            if char in ('"', "'"):
                quote = char
                cursor += 1
                while cursor < len(line):
                    if line[cursor] == "\\":
                        cursor += 2
                    elif line[cursor] == quote:
                        cursor += 1
                        break
                    else:
                        cursor += 1
                continue
            tokens.append(char)
            cursor += 1
        if "".join(tokens).strip():
            count += 1
    return count

def report():
    files = subprocess.check_output(["git", "ls-files", "-z", "--", "*.mbt"], cwd=ROOT).decode("utf-8").split("\0")
    records = []
    for name in files:
        path = Path(name)
        if not name or EXCLUDED.intersection(path.parts) or "test" in path.stem:
            continue
        records.append({"path": path.as_posix(), "codeLines": code_lines((ROOT / path).read_text(encoding="utf-8-sig"))})
    return {"definition": "tracked production MoonBit tokens outside comments and string/template bodies",
            "files": records, "total": sum(record["codeLines"] for record in records)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--min", type=int, default=4000)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = report()
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        for record in result["files"]:
            print(f'{record["codeLines"]:5} {record["path"]}')
        print(f'TOTAL {result["total"]} / REQUIRED {args.min}')
    raise SystemExit(0 if result["total"] >= args.min else 1)

if __name__ == "__main__":
    main()
