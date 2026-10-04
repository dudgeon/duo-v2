"""Spike S13 parity: the POC's own CLI with its ONNX model vs Core ML (fp32, fp16).

Pass (SRCH § 12): every POC golden top-1 unchanged; scores within a tolerance set here.
"""
import hashlib, json, os, pathlib, shutil, subprocess, sys, tempfile
import numpy as np

HERE = pathlib.Path(__file__).parent
POC = pathlib.Path.home() / "repos/smol-sim-search"
SKILL = POC / "skills/smol-sim-search"
sys.path.insert(0, str(POC / "tests"))
from conftest import GOLDEN  # the POC's golden set, unchanged

def assemble(dest):
    src = POC / "vendor/models/bge-small"
    meta = json.loads((src / "model.json").read_text())
    out = dest / "bge-small"; out.mkdir(parents=True, exist_ok=True)
    for name, want in meta["files_sha256"].items():
        data = b"".join(p.read_bytes() for p in sorted(src.glob(f"{name}.part*")) or [src / name])
        assert hashlib.sha256(data).hexdigest() == want
        (out / name).write_bytes(data)
    (out / ".sem-revision").write_text(meta["revision"])
    return dest

def run(models, variant, cu="ALL"):
    proj = pathlib.Path(tempfile.mkdtemp()) / "proj"; proj.mkdir()
    shutil.copytree(POC / "tests/fixtures", proj / "fx")
    sem_home = proj / ".sem"
    env = {k: v for k, v in os.environ.items() if not k.startswith("SEM_")}
    env.update(PYTHONPATH=f"{HERE/'hook'}:{SKILL}", PYTHONDONTWRITEBYTECODE="1", SEM_HOME=str(sem_home),
               TMPDIR=str(sem_home / "tmp"), XDG_CACHE_HOME=str(sem_home / "cache"), SEM_QUIET="1",
               SEM_MODELS_DIR=str(models))
    if variant != "onnx":
        env["DUO_COREML"] = str(HERE / "out" / f"bge-small-{variant}.mlpackage"); env["DUO_CU"] = cu
    sem = lambda *a: subprocess.run([sys.executable, "-P", "-m", "sem", *a], cwd=proj, env=env,
                                    capture_output=True, text=True, timeout=900)
    p = sem("index", "fx"); assert p.returncode == 0, p.stderr
    out = {}
    for q, _ in GOLDEN:
        r = json.loads(sem("search", q, "-k", "5", "--json").stdout)["results"]
        out[q] = [(x["path"], x["score"]) for x in r]
    return out

models = assemble(pathlib.Path(tempfile.mkdtemp()))
ref = run(models, "onnx")
report = {}
for variant, cu in [("fp32", "CPU_ONLY"), ("fp32", "ALL"), ("fp16", "ALL"), ("fp16", "CPU_AND_NE")]:
    got = run(models, variant, cu)
    top1 = sum(got[q][0][0].endswith(exp) for q, exp in GOLDEN)
    same_top1_as_ref = sum(got[q][0][0] == ref[q][0][0] for q, _ in GOLDEN)
    diffs = [abs(gs - rs) for q, _ in GOLDEN for (gp, gs), (rp, rs) in zip(got[q], ref[q]) if gp == rp]
    order_same = sum([p for p, _ in got[q]] == [p for p, _ in ref[q]] for q, _ in GOLDEN)
    report[f"{variant}/{cu}"] = dict(golden_top1=f"{top1}/{len(GOLDEN)}", same_top1_as_onnx=f"{same_top1_as_ref}/{len(GOLDEN)}",
                                    top5_order_same=f"{order_same}/{len(GOLDEN)}", max_score_diff=round(max(diffs), 5),
                                    mean_score_diff=round(float(np.mean(diffs)), 6))
ref_top1 = sum(ref[q][0][0].endswith(exp) for q, exp in GOLDEN)
print(json.dumps({"onnx_golden_top1": f"{ref_top1}/{len(GOLDEN)}", **report}, indent=1))
