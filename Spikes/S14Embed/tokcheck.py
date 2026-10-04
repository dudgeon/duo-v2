"""S14: the Swift WordPiece must produce the same ids as Hugging Face tokenizers (the POC's)."""
import json, pathlib, subprocess, sys
from tokenizers import Tokenizer
POC = pathlib.Path.home() / "repos/smol-sim-search"
sys.path.insert(0, str(POC / "tests"))
from conftest import GOLDEN
tok = Tokenizer.from_file(str(pathlib.Path(__file__).parent.parent / "S13CoreML/hf/bge-small/tokenizer.json"))
tok.enable_truncation(512)
prefix = "Represent this sentence for searching relevant passages: "
texts = [prefix + q for q, _ in GOLDEN]
texts += [p.read_text(errors="ignore") for p in sorted((POC / "tests/fixtures").rglob("*")) if p.is_file() and p.suffix != ".pdf"]
texts += ["Café naïve résumé — ÉLAN", "東京で寿司を食べた", "emoji 🎉 and ✓ marks", "C++ / C# != F#; a->b; x_y-z",
          "https://example.com/a?b=c&d=e#f", "tab\tand\r\nnewlines\x00null", "ＦＵＬＬＷＩＤＴＨ ｔｅｘｔ", "İstanbul ß ﬁ ligature",
          "word" * 40, "‘curly’ “quotes” …ellipsis", "Ünïcödé çömbïnïng: é"]
ref = [e.ids for e in tok.encode_batch(texts)]
out = subprocess.run([str(pathlib.Path(__file__).parent / ".build/debug/S14Embed"), "tokens",
                      str(pathlib.Path(__file__).parent.parent / "S13CoreML/hf/bge-small/vocab.txt")],
                     input=json.dumps(texts), capture_output=True, text=True, check=True)
mine = json.loads(out.stdout)
bad = [(t[:60], r[:12], m[:12]) for t, r, m in zip(texts, ref, mine) if r != m]
print(f"{len(texts) - len(bad)}/{len(texts)} texts tokenize identically")
for b in bad: print("  differs:", b)
