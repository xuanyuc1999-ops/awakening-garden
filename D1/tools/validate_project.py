"""Run the packaged style's native input-driven gameplay and visual checks."""
import argparse
import hashlib
import json
import subprocess
import time
import uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text(encoding="utf-8"))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
parser=argparse.ArgumentParser()
parser.add_argument("--godot",required=True)
parser.add_argument("--headless",action="store_true")
parser.add_argument("--output",type=Path)
args=parser.parse_args()
info=read(ROOT/"project-info.json")
style=info["style"]
attempt=uuid.uuid4().hex
output=(args.output or ROOT/"docs/validation"/attempt).resolve()
output.mkdir(parents=True,exist_ok=True)
farmer=read(ROOT/"art/farmer-r1/farmer.json")
asset=ROOT/farmer["path"][6:]
assert sha(asset)==farmer["sha256"]
snap={p.relative_to(ROOT).as_posix():sha(p) for p in ROOT.rglob("*") if p.is_file()
      and ".godot" not in p.parts and "docs" not in p.relative_to(ROOT).parts
      and p.suffix not in (".log",".import") and p.name!="package-manifest.json"}
digest=hashlib.sha256(json.dumps(snap,sort_keys=True).encode()).hexdigest()
command=[args.godot,"--path",str(ROOT),"--resolution","1280x800","--fixed-fps","60",
         "--script",f"res://art/refinement-r3/{style}/validate.gd","--log-file",str(output/"godot.log")]
if args.headless:command.append("--headless")
command+=["--","--autoplay","--output",str(output),"--attempt-id",attempt,
          "--binding-digest",digest,"--farmer-source-sha256",farmer["sha256"]]
started=time.monotonic()
try:
    p=subprocess.run(command,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=150,
                     creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
except subprocess.TimeoutExpired:
    (output/"summary.json").write_text(json.dumps({"style":style,"passed":False,
        "errors":["Native validation timed out after 150 seconds"],"checks":0},indent=2),encoding="utf-8")
    print(json.dumps({"style":style,"passed":False,"errors":["Native validation timed out"]}))
    raise SystemExit(1)
log=p.stdout+p.stderr
(output/"process.log").write_text(log,encoding="utf-8")
report_path=output/("smoke.json" if args.headless else "visual-smoke.json")
report=read(report_path) if report_path.exists() else {}
errors=[line for line in log.splitlines() if any(x in line for x in ("SCRIPT ERROR","Parse Error","ERROR:"))]
if report.get("status")!="pass":errors.append("Native gameplay did not pass")
checks=report.get("checks",[])
if len(checks)!=61 or not all(c["passed"] for c in checks):errors.append("61 passing checks required")
if not args.headless and len(list(output.glob("*.png")))!=16:errors.append("16 rendered captures required")
if report.get("attempt_id")!=attempt or report.get("binding_digest")!=digest:errors.append("Evidence identity mismatch")
if report.get("farmer_report",{}).get("source_sha256")!=farmer["sha256"]:errors.append("Farmer model mismatch")
changed=[path for path,h in snap.items() if not (ROOT/path).is_file() or sha(ROOT/path)!=h]
if changed:errors.append("Source drift: "+",".join(changed))
summary={"style":style,"passed":p.returncode==0 and not errors,"checks":len(checks),
         "errors":errors,"rendered":not args.headless,"captures":len(list(output.glob("*.png"))),
         "elapsed_seconds":round(time.monotonic()-started,2),"engine":report.get("engine"),
         "original_input_loop":True,"human_art_acceptance":"pending","source_snapshot":snap}
(output/"summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({k:v for k,v in summary.items() if k!="source_snapshot"},ensure_ascii=False))
raise SystemExit(0 if summary["passed"] else 1)
