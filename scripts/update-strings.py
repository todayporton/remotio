#!/usr/bin/env python3
"""ソースから翻訳対象の文字列を抜き出し、翻訳ファイルを更新する。

- ja.lproj は抜き出した文字列そのもの(キー)を値にして作り直す。日本語の訳が抜けて英語が出るのを防ぐ。
- en.lproj は既存の訳を残し、新しい文字列を英語の訳が未入力の印付きで追加する。使われなくなった訳は消す。
- --check を付けると、ファイルを書き換えずに、英語の訳の不足があれば失敗する。
"""
import glob, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOC = os.path.join(ROOT, "Resources", "Localization")
TODO = "TODO: "


def extract():
    out = tempfile.mkdtemp()
    subprocess.run(["swift", "build", "-c", "release", "--product", "RemotioApp",
                    "-Xswiftc", "-emit-localized-strings", "-Xswiftc", "-emit-localized-strings-path", "-Xswiftc", out],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    keys = {}
    for path in sorted(glob.glob(os.path.join(out, "*.stringsdata"))):
        data = json.load(open(path))
        for entry in data["tables"].get("Localizable", []):
            source = os.path.relpath(data["source"], ROOT)
            keys.setdefault(entry["key"], f'{source}:{entry["location"]["startingLine"]}')
    return keys


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def parse(path):
    if not os.path.exists(path):
        return {}
    pattern = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', re.M)
    unescape = lambda s: s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
    return {unescape(k): unescape(v) for k, v in pattern.findall(open(path, encoding="utf-8").read())}


def write(path, entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("/* scripts/update-strings.py で生成。英語の訳だけを編集する */\n\n")
        for key, (value, where) in sorted(entries.items(), key=lambda item: item[1][1]):
            f.write(f"/* {where} */\n\"{escape(key)}\" = \"{escape(value)}\";\n\n")


def main():
    keys = extract()
    en_path = os.path.join(LOC, "en.lproj", "Localizable.strings")
    english = parse(en_path)
    missing = [k for k in keys if english.get(k, TODO).startswith(TODO)]
    if "--check" in sys.argv:
        for key in missing:
            print(f"英語の訳がありません: {key} ({keys[key]})")
        unused = sorted(set(english) - set(keys))
        for key in unused:
            print(f"使われていない訳: {key}")
        sys.exit(1 if missing or unused else 0)
    write(os.path.join(LOC, "ja.lproj", "Localizable.strings"), {k: (k, w) for k, w in keys.items()})
    write(en_path, {k: (english.get(k, TODO + k), w) for k, w in keys.items()})
    print(f"{len(keys)} 件。英語の訳が未入力: {len(missing)} 件")


main()
