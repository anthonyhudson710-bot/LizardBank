#!/usr/bin/env python3
"""Dependency-free structural validation; not a replacement for GIANTS TestRunner."""
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_SUFFIXES = {"scripts": {".lua"}, "gui": {".xml"}, "l10n": {".xml"}, "assets": {".dds", ".png"}}
ROOT_FILES = ("modDesc.xml", "README.md", "LICENSE", "LICENSE.md", "LICENSE.txt")


def package_files(root):
    paths = [root / name for name in ROOT_FILES if (root / name).is_file()]
    for directory, suffixes in RUNTIME_SUFFIXES.items():
        if (root / directory).exists():
            paths.extend(path for path in (root / directory).rglob("*") if path.is_file() and path.suffix.lower() in suffixes)
    return sorted(paths, key=lambda path: path.relative_to(root).as_posix())


def validate(root=ROOT):
    errors, warnings = [], []
    files = package_files(root)
    names = {path.relative_to(root).as_posix() for path in files}
    names_folded = {name.casefold(): name for name in names}
    if len(names_folded) != len(names):
        errors.append("Runtime filenames differ only by case")
    if "modDesc.xml" not in names:
        return ["Missing modDesc.xml"], warnings
    xml = {}
    for path in files:
        if path.is_symlink():
            errors.append("Symlinks must not be packaged: " + str(path.relative_to(root)))
        if path.suffix == ".xml":
            try:
                xml[path.relative_to(root).as_posix()] = ET.parse(path).getroot()
            except ET.ParseError as exc:
                errors.append(str(path.relative_to(root)) + ": " + str(exc))
    manifest = xml.get("modDesc.xml")
    if manifest is None:
        return errors, warnings
    if manifest.tag != "modDesc":
        errors.append("modDesc.xml must have a modDesc root")
    version = manifest.findtext("version") or ""
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:\.\d+)?", version):
        errors.append("Manifest version must contain three or four numeric components")
    bootstrap = root / "scripts/LizardBank.lua"
    if bootstrap.is_file():
        declared = re.search(r'\bVERSION\s*=\s*"([^"]+)"', bootstrap.read_text(encoding="utf-8"))
        if declared is None or declared.group(1) != version:
            errors.append("Manifest and diagnostic mod versions must match")
    if not manifest.get("descVersion", "").isdigit():
        errors.append("modDesc.xml must have a numeric descVersion")
    for field in ("author", "title/en", "description/en", "iconFilename"):
        if not manifest.findtext(field):
            errors.append("Missing manifest value: " + field)
    multiplayer = manifest.find("multiplayer")
    if multiplayer is None or multiplayer.get("supported") != "false":
        errors.append("First playable manifest must declare multiplayer supported=false")

    def reference(value, source):
        value = value.strip()
        if not value or value.startswith("$"):
            return
        normalized = PurePosixPath(value)
        if "\\" in value or normalized.is_absolute() or ".." in normalized.parts:
            errors.append(source + ": invalid relative resource path " + value)
        elif value not in names:
            actual = names_folded.get(value.casefold())
            errors.append(source + ": " + ("resource case mismatch: " + value + " (actual " + actual + ")" if actual else "missing or excluded resource " + value))

    localizations = set()
    for name, tree in xml.items():
        seen = set()
        if name.startswith("l10n/") or name == "modDesc.xml":
            for element in tree.iter("text"):
                key = element.get("name")
                if key:
                    if key in seen:
                        errors.append(name + ": duplicate localization " + key)
                    seen.add(key)
                    if name.endswith("_en.xml") or name == "modDesc.xml":
                        localizations.add(key)
        for element in tree.iter():
            if element.tag in ("iconFilename",) and element.text:
                reference(element.text, name)
            for attribute, value in element.attrib.items():
                if attribute in ("filename", "imageFilename", "iconFilename", "profilesFilename"):
                    reference(value, name)
                if attribute == "filenamePrefix":
                    reference(value + "_en.xml", name)

    lua = "\n".join(path.read_text(encoding="utf-8") for path in files if path.suffix == ".lua")
    lua_functions = set(re.findall(r"function\s+[\w.]+[:.]([A-Za-z_]\w*)\s*\(", lua))
    for name, tree in xml.items():
        text = (root / name).read_text(encoding="utf-8")
        for key in set(re.findall(r"\$l10n_([A-Za-z0-9_]+)", text)):
            if key not in localizations:
                errors.append(name + ": unresolved English localization " + key)
        if name.startswith("gui/"):
            for element in tree.iter():
                for attribute, value in element.attrib.items():
                    if attribute.startswith("on") and attribute[2:3].isupper() and value not in lua_functions:
                        # Built-in callbacks such as onClickBack can be inherited.
                        warnings.append(name + ": callback " + value + " is inherited or not declared in mod Lua; verify in game")
    for value in set(re.findall(r'''["']((?:scripts|gui|l10n|assets)/[^"'\n]+\.(?:lua|xml|dds|png))["']''', lua)):
        reference(value, "Lua literal")
    icon = root / (manifest.findtext("iconFilename") or "assets/icon.dds")
    if icon.is_file() and icon.suffix.lower() == ".dds":
        data = icon.read_bytes()
        if len(data) < 128 or data[:4] != b"DDS ":
            errors.append("Icon is not a valid DDS container")
        else:
            header = struct.unpack("<31I", data[4:128])
            if header[0] != 124 or header[2:4] != (512, 512) or header[6] != 10 or data[84:88] != b"DXT5":
                errors.append("Icon must be 512 x 512 DXT5 with 10 mipmap levels")
            expected = 128 + sum(max(1, (512 >> level)//4)**2 * 16 for level in range(10))
            if len(data) != expected:
                errors.append("Icon DDS payload size does not match all mipmaps")
    if not any(name.startswith("scripts/") for name in names):
        errors.append("No Lua scripts are packaged")
    if not any(name.startswith("gui/") for name in names):
        errors.append("No GUI definitions are packaged")
    if not any(name.startswith("l10n/") for name in names):
        errors.append("No localization files are packaged")
    return errors, sorted(set(warnings))


if __name__ == "__main__":
    errors, warnings = validate()
    for warning in warnings:
        print("NOTE:", warning)
    for error in errors:
        print("ERROR:", error, file=sys.stderr)
    if not errors:
        print("Validated XML, manifest, local resources, localizations, callbacks, and DDS structure.")
    sys.exit(bool(errors))
