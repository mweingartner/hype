#!/usr/bin/env python3
"""Generate Sources/HypeCore/AI/BuiltInModel/BuiltInModelManifests.swift.

Reads MLX model snapshots from the local Hugging Face cache and pins every
runtime file by size and SHA-256, so Hype's Built-in model downloader can verify
what it fetches. Re-run this whenever a Built-in model variant changes:

    python3 scripts/built-in-model/generate_manifest.py

Nothing is downloaded: the snapshot must already be in ~/.cache/huggingface/hub
(e.g. via `hf download <repo>`).
"""

from __future__ import annotations

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTPUT = os.path.join(ROOT, "Sources/HypeCore/AI/BuiltInModel/BuiltInModelManifests.swift")
HUB = os.path.expanduser(os.environ.get("HF_HUB_CACHE", "~/.cache/huggingface/hub"))

# Only files the MLX runtime reads. READMEs, .gitattributes and vendor-specific
# Python tool parsers are not part of the package Hype installs.
RUNTIME_SUFFIXES = (".safetensors", ".json", ".jinja", ".txt", ".model")

GIB = 1 << 30

# Optional per variant: "toolCallSyntax": ".xmlFunction" when the MLX runtime
# cannot infer the model's tool-call markup from its architecture name (e.g.
# Granite 4.2, model_type "granite", speaks Qwen3-Coder's <function=…> XML).
VARIANTS = [
    {
        "property": "standard",
        "id": "qwen3.8-27b-4bit",
        "displayName": "Qwen3.8 27B (4-bit)",
        "summary": "Dense 27B hybrid model. The most accurate HypeTalk author in Hype's real-tools tournament (89.8%), at about 13 s per request on an M5 Max. Fits a 32 GB Mac.",
        "tier": ".standard",
        "repo": "mlx-community/Qwen3.8-27B-4bit",
        "license": "Apache-2.0",
        "licenseURL": "https://huggingface.co/Qwen/Qwen3.8-27B/blob/main/LICENSE",
        # 16 full-attention layers x 4 KV heads x 256 head dim x (K+V) x 2 bytes.
        "kvBytesPerToken": 16 * 4 * 256 * 2 * 2,
        "fixedOverheadBytes": int(1.75 * GIB),
        "nativeContextTokens": 262_144,
        "minimumPhysicalMemoryGB": 32,
        "recommendedPhysicalMemoryGB": 32,
        "supportsVision": True,
        "thinkingControl": '.templateFlag("enable_thinking")',
    },
    {
        "property": "max",
        "id": "qwen3-coder-next-80b-4bit",
        "displayName": "Qwen3 Coder Next 80B-A3B (4-bit)",
        "summary": "80B mixture-of-experts coding model, 3B active per token. The fastest: about 5 s per request and 60+ tokens/s on an M5 Max, 83.5% in the real-tools tournament. Needs a 96 GB+ Mac.",
        "tier": ".max",
        "repo": "mlx-community/Qwen3-Coder-Next-4bit",
        "license": "Apache-2.0",
        "licenseURL": "https://huggingface.co/Qwen/Qwen3-Coder-Next/blob/main/LICENSE",
        # 12 full-attention layers x 2 KV heads x 256 head dim x (K+V) x 2 bytes.
        "kvBytesPerToken": 12 * 2 * 256 * 2 * 2,
        "fixedOverheadBytes": int(3 * GIB),
        "nativeContextTokens": 262_144,
        "minimumPhysicalMemoryGB": 96,
        "recommendedPhysicalMemoryGB": 96,
        "supportsVision": False,
        "thinkingControl": ".none",
    },
]


def snapshot_dir(repo: str) -> tuple[str, str]:
    base = os.path.join(HUB, "models--" + repo.replace("/", "--"), "snapshots")
    if not os.path.isdir(base):
        sys.exit(f"error: {repo} is not in the local Hugging Face cache ({base})")
    revisions = sorted(os.listdir(base))
    if len(revisions) != 1:
        sys.exit(f"error: expected exactly one snapshot for {repo}, found {revisions}")
    return revisions[0], os.path.join(base, revisions[0])


def sha256_of(path: str) -> str:
    real = os.path.realpath(path)
    blob = os.path.basename(real)
    # LFS blobs in the HF cache are named by their SHA-256.
    if len(blob) == 64 and all(c in "0123456789abcdef" for c in blob):
        return blob
    digest = hashlib.sha256()
    with open(real, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def runtime_files(directory: str) -> list[tuple[str, int, str]]:
    found = []
    for root, _, names in os.walk(directory):
        for name in names:
            if not name.endswith(RUNTIME_SUFFIXES):
                continue
            path = os.path.join(root, name)
            relative = os.path.relpath(path, directory)
            found.append((relative, os.path.getsize(os.path.realpath(path)), sha256_of(path)))
    return sorted(found)


def swift_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(variant: dict) -> str:
    revision, directory = snapshot_dir(variant["repo"])
    files = runtime_files(directory)
    lines = [
        f"    static let {variant['property']} = BuiltInModelVariant(",
        f"        id: {swift_string(variant['id'])},",
        f"        displayName: {swift_string(variant['displayName'])},",
        f"        summary: {swift_string(variant['summary'])},",
        f"        tier: {variant['tier']},",
        f"        huggingFaceRepo: {swift_string(variant['repo'])},",
        f"        revision: {swift_string(revision)},",
        "        files: [",
    ]
    for path, size, digest in files:
        lines.append(
            f"            BuiltInModelFile(path: {swift_string(path)}, size: {size}, sha256: {swift_string(digest)}),"
        )
    lines += [
        "        ],",
        f"        license: {swift_string(variant['license'])},",
        f"        licenseURL: {swift_string(variant['licenseURL'])},",
        f"        kvBytesPerToken: {variant['kvBytesPerToken']},",
        f"        fixedOverheadBytes: {variant['fixedOverheadBytes']},",
        f"        nativeContextTokens: {variant['nativeContextTokens']},",
        f"        minimumPhysicalMemoryGB: {variant['minimumPhysicalMemoryGB']},",
        f"        recommendedPhysicalMemoryGB: {variant['recommendedPhysicalMemoryGB']},",
        f"        supportsVision: {'true' if variant['supportsVision'] else 'false'},",
        f"        thinkingControl: {variant['thinkingControl']}"
        + (f",\n        toolCallSyntax: {variant['toolCallSyntax']}" if variant.get("toolCallSyntax") else ""),
        "    )",
    ]
    return "\n".join(lines)


def main() -> None:
    body = "\n\n".join(render(variant) for variant in VARIANTS)
    source = (
        "// GENERATED by scripts/built-in-model/generate_manifest.py — do not edit by hand.\n"
        "// Pins every runtime file of each Built-in model variant by size and SHA-256.\n\n"
        "import Foundation\n\n"
        "enum BuiltInModelManifests {\n"
        f"{body}\n"
        "}\n"
    )
    with open(OUTPUT, "w", encoding="utf-8") as handle:
        handle.write(source)
    print(f"wrote {os.path.relpath(OUTPUT, ROOT)}")


if __name__ == "__main__":
    main()
