"""Small synthetic SQLite fixtures only; never downloads or commits map data."""
import hashlib
import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("prepare-vietnam-map.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class VietnamManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.file = Path(self.temp.name) / "vietnam.mbtiles"
        with sqlite3.connect(self.file) as db:
            db.execute("CREATE TABLE metadata(name TEXT PRIMARY KEY, value TEXT)")
            db.executemany("INSERT INTO metadata VALUES (?,?)", [
                ("country_code", "VN"), ("format", "png"), ("scheme", "tms"),
                ("bounds", "102,8,110,24"), ("minzoom", "5"), ("maxzoom", "5"),
                ("attribution", "© OpenStreetMap contributors")])
            db.execute("CREATE TABLE tiles(zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB)")
            db.execute("INSERT INTO tiles VALUES (5,25,18,?)", (prepare.PNG + b"synthetic",))

    def manifest(self):
        return prepare.make_manifest(self.file, "https://example.com/vietnam.mbtiles", "2026-10")

    def modify(self, sql):
        with sqlite3.connect(self.file) as db:
            db.execute(sql)

    def test_valid_hash_size_and_country(self):
        result = self.manifest()
        self.assertEqual(result["countryCode"], "VN")
        self.assertEqual(result["byteCount"], self.file.stat().st_size)
        self.assertEqual(result["sha256"], hashlib.sha256(self.file.read_bytes()).hexdigest())

    def test_foreign_country(self):
        self.modify("UPDATE metadata SET value='US' WHERE name='country_code'")
        with self.assertRaises(ValueError):
            self.manifest()

    def test_world_bounds(self):
        self.modify("UPDATE metadata SET value='-180,-85,180,85' WHERE name='bounds'")
        with self.assertRaises(ValueError):
            self.manifest()

    def test_vector_data_rejected(self):
        self.modify("UPDATE metadata SET value='pbf' WHERE name='format'")
        with self.assertRaises(ValueError):
            self.manifest()

    def test_empty_package(self):
        self.modify("DELETE FROM tiles")
        with self.assertRaises(ValueError):
            self.manifest()

    def test_tile_outside_region(self):
        self.modify("UPDATE tiles SET tile_column=1")
        with self.assertRaises(ValueError):
            self.manifest()

    def test_bad_tms_row(self):
        self.modify("UPDATE tiles SET tile_row=32")
        with self.assertRaises(ValueError):
            self.manifest()

    def test_bad_png(self):
        self.modify("UPDATE tiles SET tile_data=X'01020304'")
        with self.assertRaises(ValueError):
            self.manifest()

    def test_unsafe_or_public_tile_download_sources(self):
        for url in ["http://example.com/vn", "https://tile.openstreetmap.org/a", "https://openstreetmap.org/a",
                    "https://user:pass@example.com/a", "file:///vietnam.mbtiles"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                prepare.validate_source(url)


if __name__ == "__main__":
    unittest.main()
