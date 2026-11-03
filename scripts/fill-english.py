#!/usr/bin/env python3
"""Resources/Localization/en-translations.py の訳を en.lproj に反映する。"""
import os, runpy, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EN = runpy.run_path(os.path.join(ROOT, "Resources", "Localization", "en-translations.py"))["EN"]
path = os.path.join(ROOT, "Resources", "Localization", "en.lproj", "Localizable.strings")
escape = lambda s: s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
unescape = lambda s: s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
pattern = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', re.M)
text = open(path, encoding="utf-8").read()
filled = 0

def replace(match):
    global filled
    key = unescape(match.group(1))
    if key in EN:
        filled += 1
        return f'"{escape(key)}" = "{escape(EN[key])}";'
    return match.group(0)

open(path, "w", encoding="utf-8").write(pattern.sub(replace, text))
print(f"{filled} 件を反映しました")
