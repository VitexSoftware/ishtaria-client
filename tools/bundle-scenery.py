#!/usr/bin/env python3
"""Copy the Kenney kit models the server's generated places use into assets/kenney/.

Usage: bundle-scenery.py MODELS.json KITS_DIR
MODELS.json is written by `SCENERY_MODELS=models.json cargo test list_models` in ishtaria-server.
KITS_DIR holds the unzipped kits as downloaded from kenney.nl: graveyard-kit, fantasy-town-kit,
castle-kit, retro-fantasy-kit and pirate-kit (each with Models/GLB format/). Only the used models and
the textures they name are copied, with the kit's licence.
"""
import json
import pathlib
import shutil
import struct
import sys

KITS = {"graveyard": "graveyard-kit", "town": "fantasy-town-kit", "castle": "castle-kit",
        "retro": "retro-fantasy-kit", "pirate": "pirate-kit"}
root = pathlib.Path(__file__).resolve().parent.parent / "assets" / "kenney"
models = json.loads(pathlib.Path(sys.argv[1]).read_text())
kits = pathlib.Path(sys.argv[2])


def texture_names(glb: pathlib.Path):
    data = glb.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20:20 + length])
    return [image["uri"] for image in document.get("images", []) if "uri" in image]


copied = 0
for model in models:
    kit, name = model.split(".", 1)
    if kit not in KITS:
        continue  # the Quaternius models are bundled by hand with their own licences
    source = kits / KITS[kit] / "Models" / "GLB format"
    target = root / KITS[kit]
    (target / "Textures").mkdir(parents=True, exist_ok=True)
    shutil.copy(source / f"{name}.glb", target / f"{name}.glb")
    for uri in texture_names(source / f"{name}.glb"):
        shutil.copy(source / uri, target / uri)
    licence = kits / KITS[kit] / "License.txt"
    if not (target / "License.txt").exists():
        shutil.copy(licence, target / "License.txt")
    copied += 1
print(f"{copied} models bundled")
