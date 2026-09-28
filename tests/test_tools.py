"""Isolated packaging/resource fixtures; no native FS25 validation is implied."""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def load_tool(name):
    spec = importlib.util.spec_from_file_location("lizard_bank_test_" + name, ROOT / "tools" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validator = load_tool("validate")
icon = load_tool("make_icon")
with mock.patch.dict(sys.modules, {"validate": validator, "make_icon": icon}):
    builder = load_tool("build")


class ToolTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lizard-bank-tools-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # Copy actual resource inputs, but never the repository's dist or logs.
        for path in validator.package_files(ROOT) + [ROOT / "assets/icon.svg"]:
            destination = self.root / path.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)

    def errors(self):
        errors, _ = validator.validate(self.root)
        return "\n".join(errors)

    def manifest(self, edit):
        path = self.root / "modDesc.xml"
        tree = ET.parse(path)
        edit(tree.getroot())
        tree.write(path, encoding="utf-8", xml_declaration=True)

    def build(self):
        # Both paths must be patched: build.generate has a bound default ROOT.
        with mock.patch.object(builder, "ROOT", self.root), mock.patch.object(builder, "generate", side_effect=lambda: icon.generate(self.root)):
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return builder.main()

    def test_current_resource_tree_validates_without_native_claim(self):
        errors, _ = validator.validate(self.root)
        self.assertEqual(errors, [])

    def test_missing_manifest_and_malformed_xml_are_rejected(self):
        manifest = self.root / "modDesc.xml"
        original = manifest.read_bytes()
        manifest.unlink()
        self.assertIn("Missing modDesc.xml", self.errors())
        manifest.write_bytes(original)
        (self.root / "gui/BankScreen.xml").write_text("<GUI><broken>", encoding="utf-8")
        self.assertIn("gui/BankScreen.xml:", self.errors())
        manifest.write_text("<modDesc>", encoding="utf-8")
        self.assertIn("modDesc.xml:", self.errors())

    def test_manifest_root_version_description_and_required_fields(self):
        self.manifest(lambda root: setattr(root, "tag", "wrongRoot"))
        self.assertIn("modDesc.xml must have a modDesc root", self.errors())
        self.manifest(lambda root: root.find("version").__setattr__("text", "invalid"))
        self.assertIn("three or four numeric components", self.errors())
        self.manifest(lambda root: root.find("version").__setattr__("text", "99.99.99"))
        self.assertIn("Manifest and diagnostic mod versions must match", self.errors())
        self.manifest(lambda root: root.set("descVersion", "abc"))
        self.assertIn("numeric descVersion", self.errors())
        for field in ("author", "title/en", "description/en", "iconFilename"):
            with self.subTest(field=field):
                self.manifest(lambda root, field=field: root.find(field).__setattr__("text", ""))
                self.assertIn("Missing manifest value: " + field, self.errors())

    def test_multiplayer_manifest_must_explicitly_disable_support(self):
        self.manifest(lambda root: root.find("multiplayer").set("supported", "true"))
        self.assertIn("multiplayer supported=false", self.errors())
        self.manifest(lambda root: root.remove(root.find("multiplayer")))
        self.assertIn("multiplayer supported=false", self.errors())

    def test_resource_paths_reject_traversal_absolute_backslash_and_missing(self):
        source = "extraSourceFiles/sourceFile"
        for value in ("../outside.lua", "/absolute.lua", "scripts\\wrong.lua"):
            with self.subTest(value=value):
                self.manifest(lambda root, value=value: root.find(source).set("filename", value))
                self.assertIn("invalid relative resource path " + value, self.errors())
        for value in ("scripts/absent.lua", "tools/ignored.lua"):
            with self.subTest(value=value):
                path = self.root / value
                if value.startswith("tools/"):
                    path.parent.mkdir(); path.write_text("-- excluded developer file", encoding="utf-8")
                self.manifest(lambda root, value=value: root.find(source).set("filename", value))
                self.assertIn("missing or excluded resource " + value, self.errors())

    def test_resource_case_mismatch_and_case_alias_inventory(self):
        source = "extraSourceFiles/sourceFile"
        self.manifest(lambda root: root.find(source).set("filename", root.find(source).get("filename").upper()))
        self.assertIn("resource case mismatch", self.errors())
        real = self.root / "scripts/FixtureCase.lua"
        alias = self.root / "scripts/fixturecase.lua"
        real.write_text("-- fixture", encoding="utf-8")
        alias.write_text("-- fixture", encoding="utf-8")
        paths = validator.package_files(self.root)
        # Case-insensitive hosts cannot enumerate both aliases, so provide the
        # same conflicting inventory explicitly to exercise the portable rule.
        by_name = {path.relative_to(self.root).as_posix(): path for path in paths}
        by_name[real.relative_to(self.root).as_posix()] = real
        by_name[alias.relative_to(self.root).as_posix()] = alias
        with mock.patch.object(validator, "package_files", return_value=list(by_name.values())):
            self.assertIn("Runtime filenames differ only by case", self.errors())

    def test_runtime_symlinks_are_rejected(self):
        link = self.root / "scripts/linked.lua"
        try:
            link.symlink_to(self.root / "scripts/LizardBank.lua")
        except OSError as error:
            self.skipTest("Host cannot create a symlink: " + str(error))
        self.assertIn("Symlinks must not be packaged: scripts/linked.lua", self.errors())

    def test_localization_duplicates_and_unresolved_gui_keys_are_rejected(self):
        path = self.root / "l10n/l10n_en.xml"
        tree = ET.parse(path)
        existing = next(tree.getroot().iter("text"))
        tree.getroot().append(ET.Element("text", {"name": existing.get("name")}))
        tree.write(path, encoding="utf-8")
        self.assertIn("duplicate localization " + existing.get("name"), self.errors())
        gui = self.root / "gui/BankScreen.xml"
        gui.write_text(gui.read_text(encoding="utf-8").replace("$l10n_lb_title", "$l10n_fixture_missing"), encoding="utf-8")
        self.assertIn("unresolved English localization fixture_missing", self.errors())

    def test_localization_prefix_and_lua_resource_literals_are_validated(self):
        self.manifest(lambda root: root.find("l10n").set("filenamePrefix", "l10n/absent"))
        self.assertIn("missing or excluded resource l10n/absent_en.xml", self.errors())
        with (self.root / "scripts/LizardBank.lua").open("a", encoding="utf-8") as handle:
            handle.write('\nlocal fixtureResource = "assets/absent.png"\n')
        self.assertIn("Lua literal: missing or excluded resource assets/absent.png", self.errors())

    def test_inherited_gui_callbacks_are_warnings_not_invented_resolution(self):
        path = self.root / "gui/BankScreen.xml"
        path.write_text(path.read_text(encoding="utf-8").replace('onClick="onClickBack"', 'onClick="fixtureInheritedCallback"'), encoding="utf-8")
        errors, warnings = validator.validate(self.root)
        self.assertEqual(errors, [])
        self.assertTrue(any("fixtureInheritedCallback" in warning and "verify in game" in warning for warning in warnings))

    def test_missing_runtime_families_are_rejected(self):
        for directory, message in (("scripts", "No Lua scripts"), ("gui", "No GUI definitions"), ("l10n", "No localization files")):
            with self.subTest(directory=directory):
                shutil.rmtree(self.root / directory)
                self.assertIn(message, self.errors())

    def test_dds_magic_header_dimensions_mips_format_and_payload_are_checked(self):
        path = self.root / "assets/icon.dds"
        original = path.read_bytes()
        for data in (b"tiny", b"BAD!" + original[4:]):
            with self.subTest(case="container", size=len(data)):
                path.write_bytes(data)
                self.assertIn("not a valid DDS container", self.errors())
        for offset, value in ((4, 123), (12, 256), (16, 256), (28, 1), (84, int.from_bytes(b"DXT1", "little"))):
            with self.subTest(offset=offset):
                data = bytearray(original)
                struct.pack_into("<I", data, offset, value)
                path.write_bytes(data)
                self.assertIn("512 x 512 DXT5 with 10 mipmap levels", self.errors())
        for data in (original[:-1], original + b"extra"):
            with self.subTest(size=len(data)):
                path.write_bytes(data)
                self.assertIn("payload size does not match all mipmaps", self.errors())

    def test_package_allowlist_excludes_development_evidence_and_source_art(self):
        excluded = ("log.txt", "test.md", "tests/test.lua", "tools/dev.py", "docs/notes.md", "scripts/cache.pyc", "assets/raw.svg", "dist/old.zip")
        for name in excluded:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture", encoding="utf-8")
        (self.root / "LICENSE.md").write_text("fixture license", encoding="utf-8")
        names = [path.relative_to(self.root).as_posix() for path in validator.package_files(self.root)]
        self.assertEqual(names, sorted(names))
        self.assertIn("LICENSE.md", names)
        self.assertIn("assets/icon.dds", names)
        self.assertNotIn("assets/icon.svg", names)
        self.assertTrue(set(names).isdisjoint(excluded))

    def test_build_is_byte_reproducible_with_exact_payload_and_fixed_zip_metadata(self):
        self.assertEqual(self.build(), 0)
        destination = self.root / "dist/FS25_LizardBank.zip"
        first = destination.read_bytes()
        expected = {path.relative_to(self.root).as_posix(): path.read_bytes() for path in validator.package_files(self.root)}
        with zipfile.ZipFile(destination) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.namelist(), sorted(expected))
            self.assertIn("modDesc.xml", archive.namelist())
            for entry in archive.infolist():
                self.assertEqual(archive.read(entry.filename), expected[entry.filename])
                self.assertEqual(entry.date_time, (2024, 1, 1, 0, 0, 0))
                self.assertEqual(entry.external_attr >> 16, 0o100644)
                self.assertEqual(entry.create_system, 3)
                self.assertEqual(entry.compress_type, zipfile.ZIP_DEFLATED)
        self.assertEqual(self.build(), 0)
        self.assertEqual(destination.read_bytes(), first)

    def test_validation_failure_does_not_create_or_overwrite_existing_zip(self):
        self.manifest(lambda root: root.find("version").__setattr__("text", "invalid"))
        destination = self.root / "dist/FS25_LizardBank.zip"
        self.assertEqual(self.build(), 1)
        self.assertFalse(destination.exists())
        destination.parent.mkdir()
        destination.write_bytes(b"existing-package-evidence")
        self.assertEqual(self.build(), 1)
        self.assertEqual(destination.read_bytes(), b"existing-package-evidence")

    def test_icon_art_rasterization_rect_polygon_and_color_contracts(self):
        width, height, pixels = icon.rasterize(self.root / "assets/icon.svg")
        self.assertEqual((width, height, len(pixels)), (512, 512, 512 * 512))
        self.assertEqual(pixels[0], (17, 43, 37))
        self.assertEqual(pixels[25 * width + 25], (40, 72, 58))
        self.assertEqual(pixels[150 * width + 256], (217, 185, 109))
        self.assertEqual(pixels[250 * width + 130], (236, 230, 213))
        polygon = [(0, 0), (4, 0), (4, 4), (0, 4)]
        self.assertTrue(icon.inside_polygon(2, 2, polygon))
        self.assertFalse(icon.inside_polygon(-1, 2, polygon))
        self.assertFalse(icon.inside_polygon(5, 2, polygon))
        for color in ((0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255)):
            with self.subTest(color=color):
                self.assertEqual(icon.expand565(icon.rgb565(color)), color)

    def test_icon_unsupported_svg_and_wrong_dimensions_fail_before_output_write(self):
        path = self.root / "assets/icon.svg"
        destination = self.root / "assets/icon.dds"
        original = destination.read_bytes()
        path.write_text('<svg width="512" height="512"><circle fill="#ffffff"/></svg>', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Unsupported icon SVG element: circle"):
            icon.generate(self.root)
        self.assertEqual(destination.read_bytes(), original)
        path.write_text('<svg width="4" height="4"><rect x="0" y="0" width="4" height="4" fill="#ffffff"/></svg>', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "512 x 512"):
            icon.generate(self.root)
        self.assertEqual(destination.read_bytes(), original)

    def test_dxt5_small_mipmap_edge_replication_and_opaque_alpha(self):
        one = icon.compress_level(1, 1, [(255, 0, 0)])
        self.assertEqual(len(one), 16)
        self.assertEqual(one[:8], b"\xff\xff\0\0\0\0\0\0")
        self.assertEqual(struct.unpack("<HHI", one[8:]), (0xF800, 0xF800, 0))
        self.assertEqual(one, icon.compress_level(4, 4, [(255, 0, 0)] * 16))
        self.assertEqual(len(icon.compress_level(5, 3, [(0, 255, 0)] * 15)), 32)

    def test_generated_icon_full_mips_and_no_rewrite_when_unchanged(self):
        path = icon.generate(self.root)
        first, timestamp = path.read_bytes(), path.stat().st_mtime_ns
        self.assertEqual(first[:4], b"DDS ")
        self.assertEqual(struct.unpack_from("<I", first, 28)[0], 10)
        self.assertEqual(len(first), 128 + sum(max(1, (512 >> level) // 4) ** 2 * 16 for level in range(10)))
        self.assertEqual(icon.generate(self.root), path)
        self.assertEqual(path.read_bytes(), first)
        self.assertEqual(path.stat().st_mtime_ns, timestamp)


if __name__ == "__main__":
    unittest.main()
