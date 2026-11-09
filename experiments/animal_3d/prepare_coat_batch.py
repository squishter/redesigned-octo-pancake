"""Prepare each asset in isolated Blender processes; stop on any failed check."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--only")
    parser.add_argument("--blender-python", type=Path, help="Optional Python 3.11 environment with bpy==4.3.0 and numpy<2")
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    identifiers = ["ultimate_" + p.stem for p in sorted((args.source_root / "ultimate").glob("*.glb"))]
    identifiers += ["farm_" + p.stem for p in sorted((args.source_root / "farm").glob("*.blend"))]
    identifiers += ["vol2_" + p.stem.removeprefix("animal-") for p in sorted(args.source_root.glob("animal-*.glb"))]
    if args.only:
        identifiers = [i for i in identifiers if i in args.only.split(",")]
    command = ["blender", "--background", "--threads", "1", "--factory-startup", "--disable-autoexec",
               "--python-exit-code", "1", "--python", str(Path(__file__).with_name("prepare_coat_uvs.py")), "--",
               f"--source-root={args.source_root}", f"--out={args.out}"]
    if args.blender_python:
        command = [str(args.blender_python), "-c",
                   "import runpy,sys; runpy.run_path(sys.argv[1],run_name='__main__')",
                   str(Path(__file__).with_name("prepare_coat_uvs.py")), "--",
                   f"--source-root={args.source_root}", f"--out={args.out}"]
    reports = []
    for identifier in identifiers:
        path = args.out / (identifier + "_uv.json")
        if args.resume and path.exists():
            report = json.loads(path.read_text())
            glb = args.out / report["glb"]
            if glb.exists() and report.get("sha256") == hashlib.sha256(glb.read_bytes()).hexdigest():
                print(identifier, "already ready", flush=True)
                continue
        with (args.out / (identifier + ".log")).open("w") as log:
            prepare = subprocess.run(command + [f"--only={identifier}", "--no-export"], stdout=log, stderr=log)
            log.flush()
            assert prepare.returncode == 0 and f"UV_READY {identifier} " in (
                args.out / (identifier + ".log")).read_text(), identifier
            export = subprocess.run(command + [f"--export-blend={args.out / (identifier + '.blend')}"],
                                    stdout=log, stderr=log)
            log.flush()
            assert export.returncode == 0 and f"GLB_READY {identifier}" in (
                args.out / (identifier + ".log")).read_text(), identifier
        report = json.loads(path.read_text())
        report["sha256"] = hashlib.sha256((args.out / report["glb"]).read_bytes()).hexdigest()
        report["blender_exit_codes"] = [prepare.returncode, export.returncode]
        path.write_text(json.dumps(report, indent=2) + "\n")
        reports.append(report)
        print(identifier, "ready", flush=True)
    reports = [json.loads(p.read_text()) for p in sorted(args.out.glob("*_uv.json"))]
    (args.out / "uv_manifest.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
