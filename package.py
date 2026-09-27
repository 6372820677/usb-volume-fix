#!/usr/bin/env python3
"""
Package the USB Volume Fix module into a flashable zip.

The zip contains ONLY the module files (forward-slash arcnames, suitable for
KernelSU / Magisk). Repo metadata (README, LICENSE, .gitignore, this script)
is excluded.

Usage:
    python3 package.py
Output:
    usb_volume_fix_v2.zip   (in this directory)
"""
import os
import sys
import zipfile

MODULE_ROOT = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.join(MODULE_ROOT, "usb_volume_fix_v2.zip")

# Files/dirs that are repo metadata — NOT part of the flashable module.
EXCLUDE_NAMES = {
    ".git", ".gitignore", "__pycache__",
    "README.md", "LICENSE", "package.py",
    os.path.basename(OUTPUT),  # the zip itself if re-run
}


def collect_files(root):
    """Walk root, returning module files (excluding metadata + hidden)."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        # prune excluded dirs in-place so os.walk skips them
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_NAMES]
        for name in filenames:
            if name in EXCLUDE_NAMES or name.startswith("."):
                continue
            out.append(os.path.join(dirpath, name))
    return sorted(out)


def main():
    files = collect_files(MODULE_ROOT)
    if not files:
        print("No module files found in", MODULE_ROOT, file=sys.stderr)
        return 1

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as zf:
        for fp in files:
            arcname = os.path.relpath(fp, MODULE_ROOT).replace("\\", "/")
            zf.write(fp, arcname)
            print("  + {:42s} {:>6d} B".format(arcname, os.path.getsize(fp)))

    print("\nCreated: {}".format(OUTPUT))
    print("Size: {} bytes | Files: {}".format(os.path.getsize(OUTPUT), len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
