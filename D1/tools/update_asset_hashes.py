"""Update checksums after intentional local edits. No network or model generation."""
import argparse
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("--apply",action="store_true",help="Write verified local hashes to existing manifests")
args=parser.parse_args()
changes=[]
def walk(value,manifest):
    if isinstance(value,dict):
        if isinstance(value.get("path"),str) and value["path"].startswith("res://") and "sha256" in value:
            p=(ROOT/value["path"][6:]).resolve()
            assert p.is_relative_to(ROOT) and p.is_file(),value["path"]
            digest=hashlib.sha256(p.read_bytes()).hexdigest()
            if value["sha256"]!=digest:
                changes.append({"manifest":str(manifest.relative_to(ROOT)),"asset":value["path"]})
                value["sha256"]=digest
        for child in value.values():walk(child,manifest)
    elif isinstance(value,list):
        for child in value:walk(child,manifest)
for manifest in list((ROOT/"art").rglob("models.json"))+[ROOT/"art/farmer-r1/farmer.json"]:
    data=json.loads(manifest.read_text(encoding="utf-8"))
    before=len(changes);walk(data,manifest)
    if args.apply and len(changes)>before:manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"applied":args.apply,"changes":changes},ensure_ascii=False,indent=2))
