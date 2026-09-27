#!/usr/bin/env python3
"""Validate and create a reproducible, explicitly allowlisted FS25 mod ZIP."""
import hashlib
from pathlib import Path
import sys
import zipfile

from make_icon import generate
from validate import ROOT, package_files, validate


def main():
    generate()
    errors, warnings = validate(ROOT)
    for warning in warnings:
        print("NOTE:", warning)
    if errors:
        for error in errors:
            print("ERROR:", error, file=sys.stderr)
        return 1
    destination = ROOT / "dist/FS25_LizardBank.zip"
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in package_files(ROOT):
            name = path.relative_to(ROOT).as_posix()
            info = zipfile.ZipInfo(name, date_time=(2024, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None or "modDesc.xml" not in archive.namelist():
            raise RuntimeError("Archive integrity check failed")
    data = destination.read_bytes()
    print("Built:", destination)
    print("Bytes:", len(data))
    print("SHA256:", hashlib.sha256(data).hexdigest())
    print("Local structural validation passed. FS25 runtime validation is still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
