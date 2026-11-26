"""Builds release/WhatToDo.zip (the addon folder only: the .toc and the files it lists, plus LICENSE)
and release/VERSION (the .toc's version), and puts the version into the README title. Run from the repository root: python tools/build_release.py
The zip is reproducible: fixed timestamps and order, so an unchanged addon gives an identical file."""
import os, re, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "WhatToDo.toc")

def main():
    toc = open(TOC, encoding="utf-8").read()
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    files = ["WhatToDo.toc"] + [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")] + ["LICENSE"]
    out_dir = os.path.join(ROOT, "release")
    os.makedirs(out_dir, exist_ok=True)
    zpath = os.path.join(out_dir, "WhatToDo.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for name in files:
            path = os.path.join(ROOT, name.replace("\\", os.sep))
            info = zipfile.ZipInfo("WhatToDo/" + name.replace("\\", "/"), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, open(path, "rb").read())
    open(os.path.join(out_dir, "VERSION"), "w", newline="\n").write(version + "\n")
    readme = os.path.join(ROOT, "README.md")
    text = open(readme, encoding="utf-8").read()
    text = re.sub(r"\A# WhatToDo[^\n]*", "# WhatToDo " + version, text, count=1)
    open(readme, "w", encoding="utf-8", newline="").write(text)
    print(f"WhatToDo {version}: {zpath} ({os.path.getsize(zpath)} bytes, {len(files)} files)")

if __name__ == "__main__":
    main()
