import io
import sqlite3
import tempfile
import unittest
from pathlib import Path

from PIL import Image
import build_vietnam as builder


class MapBuilderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.poly = self.root / "vietnam.poly"
        self.poly.write_text("Vietnam\n1\n105.7 20.9\n105.9 20.9\n105.9 21.1\n105.7 21.1\n105.7 20.9\nEND\nEND\n")
        self.source = self.root / "test.osm"
        self.source.write_text('''<?xml version="1.0"?><osm version="0.6" generator="test">
          <node id="1" lat="21.0" lon="105.72" version="1"/>
          <node id="2" lat="21.0" lon="105.88" version="1"/>
          <node id="3" lat="21.01" lon="105.8" version="1"><tag k="place" v="city"/><tag k="name" v="Hà Nội mẫu"/></node>
          <node id="4" lat="20.95" lon="105.75" version="1"/>
          <node id="5" lat="20.96" lon="105.75" version="1"/>
          <node id="6" lat="20.96" lon="105.76" version="1"/>
          <node id="7" lat="20.95" lon="105.76" version="1"/>
          <way id="1" version="1"><nd ref="1"/><nd ref="2"/><tag k="highway" v="primary"/><tag k="name" v="Đường mẫu"/></way>
          <way id="2" version="1"><nd ref="4"/><nd ref="5"/><nd ref="6"/><nd ref="7"/><nd ref="4"/><tag k="natural" v="water"/></way>
          </osm>''')

    def test_projection_roundtrip(self):
        x, y = builder.project(105.8, 21)
        lon, lat = builder.unproject(x, y)
        self.assertAlmostEqual(lon, 105.8)
        self.assertAlmostEqual(lat, 21)

    def test_polygon_and_country_mask(self):
        polygon = builder.country_polygon(self.poly)
        self.assertTrue(polygon.contains(builder.Point(builder.project(105.8, 21))))
        self.assertFalse(polygon.contains(builder.Point(builder.project(100, 21))))

    def test_real_osm_to_local_mbtiles(self):
        output = self.root / "vietnam.mbtiles"
        report = builder.build(self.source, self.poly, output, self.root / "work",
                               "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", low=7, high=8, workers=1, version="test")
        self.assertEqual(report["features"], 3)
        self.assertGreater(report["tiles"], 0)
        with sqlite3.connect(output) as db:
            metadata = dict(db.execute("SELECT name,value FROM metadata"))
            self.assertEqual(metadata["country_code"], "VN")
            self.assertEqual(metadata["scheme"], "tms")
            png = db.execute("SELECT tile_data FROM tiles LIMIT 1").fetchone()[0]
            with Image.open(io.BytesIO(png)) as image:
                self.assertEqual(image.size, (256, 256))
                self.assertEqual(image.mode, "RGBA")
                extrema = image.getchannel("A").getextrema()
                self.assertLess(extrema[0], extrema[1])
        # Run the production manifest validator against the same output.
        import importlib.util
        spec = importlib.util.spec_from_file_location("prepare", Path(__file__).parents[1] / "prepare-vietnam-map.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        manifest = module.make_manifest(output, "https://example.com/vietnam.mbtiles", "test")
        self.assertEqual(manifest["byteCount"], output.stat().st_size)


if __name__ == "__main__":
    unittest.main()
