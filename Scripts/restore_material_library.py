"""Restore the separately uploaded local art library without overwriting local work."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import zipfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def restore(archives, workspace):
    manifest = json.loads((archives / "manifest.json").read_text(encoding="utf-8"))
    expected = {item["path"]: item for item in manifest["files"]}
    # Validate every archive before extracting any file.
    for item in manifest["archives"]:
        source = archives / item["name"]
        if source.stat().st_size != item["bytes"] or digest(source) != item["sha256"]:
            raise ValueError("Archive checksum mismatch: " + source.name)
    workspace = workspace.resolve()
    restored = 0
    for item in manifest["archives"]:
        with zipfile.ZipFile(archives / item["name"]) as archive:
            for member in archive.infolist():
                relative = PurePosixPath(member.filename)
                target = (workspace / member.filename).resolve()
                if relative.is_absolute() or not target.is_relative_to(workspace):
                    raise ValueError("Unsafe archive path: " + member.filename)
                if member.is_dir():
                    continue
                record = expected[member.filename]
                if record["archive"] != item["name"]:
                    raise ValueError("Wrong source archive: " + member.filename)
                if target.exists():
                    if target.stat().st_size == record["size"] and digest(target) == record["sha256"]:
                        restored += 1
                        continue
                    raise FileExistsError("Existing local file differs; choose a fresh workspace: " + str(target))
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(member) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output, 1024 * 1024)
                if target.stat().st_size != record["size"] or digest(target) != record["sha256"]:
                    raise ValueError("Restored file checksum mismatch: " + member.filename)
                restored += 1
    if restored != len(expected):
        raise ValueError("Incomplete library restore")
    # Preserve historical files verbatim; write separate path-adjusted copies.
    sources = workspace / "MaterialSources"
    inputs = json.loads((workspace / "MonsterAssets/Video-Extract-V1/inputs.json").read_text(encoding="utf-8"))
    video_paths = {item["source"]: str(sources / (item["id"] + ".mp4")) for item in inputs}

    def remap(value):
        if isinstance(value, str):
            return video_paths.get(value, value.replace("D:\\gpt_workspace\\ios_ldd", str(workspace)))
        if isinstance(value, list):
            return [remap(item) for item in value]
        if isinstance(value, dict):
            return {key: remap(item) for key, item in value.items()}
        return value

    for original, output in [(sources / "素材接入清单_2026-11-02.json", sources / "portable-integration-catalog.json"),
                             (workspace / "MonsterAssets/Video-Extract-V1/inputs.json", sources / "portable-video-inputs.json")]:
        data = json.loads(original.read_text(encoding="utf-8"))
        adjusted = json.dumps(remap(data), ensure_ascii=False, indent=2)
        if output.exists() and output.read_text(encoding="utf-8") != adjusted:
            raise FileExistsError("Refuse to replace modified portable catalog: " + str(output))
        output.write_text(adjusted, encoding="utf-8")
    print(json.dumps({"restoredFiles": restored, "workspace": str(workspace),
                      "skillsPreview": str(workspace / "LocalEffects/index.html"),
                      "monstersPreview": str(workspace / "MonsterAssets/Video-Extract-V1/index.html")}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archives", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    options = parser.parse_args()
    restore(options.archives, options.workspace)
