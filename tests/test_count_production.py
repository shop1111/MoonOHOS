import importlib.util
from pathlib import Path
import unittest

script = Path(__file__).resolve().parents[1] / "scripts/count_production.py"
spec = importlib.util.spec_from_file_location("count_production", script)
counter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(counter)

class CountProductionTests(unittest.TestCase):
    def test_templates_comments_and_literal_bodies_are_excluded(self):
        source = '''// comment
fn hello() {
  let message = "// not a comment"
  #|native template body
  "literal only"
  /* multi
     line */ use(message)
}
'''
        self.assertEqual(counter.code_lines(source), 4)

    def test_literal_lists_and_tuples_are_excluded(self):
        source = '"a",\n("a", "b"),\n["a", "b"]\nlet values = ["a", "b"]\n)\n'
        self.assertEqual(counter.code_lines(source), 2)

    def test_nested_comments_and_escaped_quotes(self):
        self.assertEqual(counter.code_lines('/* outer /* inner */ end */ let x = "a\\\"b"\n// no'), 1)

if __name__ == "__main__":
    unittest.main()
