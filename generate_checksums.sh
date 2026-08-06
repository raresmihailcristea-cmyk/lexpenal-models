#!/usr/bin/env bash
# generate_checksums.sh — completează secțiunea `verification` din manifeste.
#
# Două moduri:
#
#   --from-huggingface            (implicit, recomandat)
#       Citește SHA256 direct din API-ul HuggingFace. Fișierele mari sunt stocate
#       prin Git LFS, iar `lfs.oid` ESTE SHA256-ul conținutului — aceeași valoare
#       pe care ai obține-o rulând `shasum -a 256` după descărcare. Nu descarcă
#       greutățile: pentru cele trei modele ale aplicației, asta ar însemna ~63 GB.
#
#   --model-dir <cale>
#       Calculează SHA256 local, dintr-un model deja descărcat. De folosit când
#       vrei să confirmi că ce ai pe disc corespunde cu ce declară manifestul.
#
# Semnătura Ed25519 se aplică peste rezumatul fișierelor, dacă e disponibilă cheia:
#   export LEXPENAL_ED25519_PRIVKEY=<cheie-privata-hex>
#
# Utilizare:
#   ./generate_checksums.sh
#   ./generate_checksums.sh --model-dir ~/.cache/huggingface/hub/models--mlx-community--Qwen3-8B-4bit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="huggingface"
MODEL_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-huggingface) MODE="huggingface"; shift ;;
        --model-dir) MODE="local"; MODEL_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "Argument necunoscut: $1" >&2; exit 2 ;;
    esac
done

command -v python3 >/dev/null || { echo "python3 este necesar." >&2; exit 1; }

if [[ -z "${LEXPENAL_ED25519_PRIVKEY:-}" ]]; then
    echo "Notă: LEXPENAL_ED25519_PRIVKEY nu e setată — se scriu doar checksum-urile SHA256."
    echo "      Semnătura garantează AUTENTICITATEA sursei; checksum-ul garantează INTEGRITATEA."
    echo ""
fi

if [[ "$MODE" == "local" ]]; then
    [[ -d "$MODEL_DIR" ]] || { echo "Directorul nu există: $MODEL_DIR" >&2; exit 1; }
    echo "Mod local: calculez SHA256 din $MODEL_DIR"
    echo "(pentru a scrie în manifest, rulează fără --model-dir; acest mod doar raportează)"
    find "$MODEL_DIR" -name '*.safetensors' -type f | while read -r file; do
        printf '  %s  %s\n' "$(shasum -a 256 "$file" | awk '{print $1}')" "$(basename "$file")"
    done
    exit 0
fi

python3 - "$SCRIPT_DIR" <<'PYTHON'
import glob, hashlib, io, json, os, sys, urllib.request

manifest_dir = sys.argv[1]
signing_key = os.environ.get("LEXPENAL_ED25519_PRIVKEY", "")

def hf_tree(model_id):
    url = f"https://huggingface.co/api/models/{model_id}/tree/main?recursive=1"
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)

# Doar fișierele care contează pentru integritate: greutățile și tokenizatorul.
# Restul sunt fișiere mici de configurare, stocate ca blob-uri git (SHA1), pe
# care HuggingFace nu le expune ca SHA256.
def relevant(entry):
    path = entry.get("path", "")
    return entry.get("type") == "file" and (
        path.endswith(".safetensors") or path == "tokenizer.json"
    )

updated = skipped = 0
for manifest_path in sorted(glob.glob(os.path.join(manifest_dir, "mlx-community-*.json"))):
    manifest = json.load(open(manifest_path))
    model_id = manifest["model_id"]
    try:
        tree = hf_tree(model_id)
    except Exception as error:
        print(f"  {model_id}: NU s-a putut citi arborele ({error})")
        skipped += 1
        continue

    files = []
    for entry in sorted(tree, key=lambda e: e.get("path", "")):
        if not relevant(entry):
            continue
        oid = (entry.get("lfs") or {}).get("oid")
        if not oid:
            # Fișier mic, versionat ca blob git — nu avem SHA256 de la sursă.
            continue
        files.append({
            "path": entry["path"],
            "sha256": oid,
            "size_bytes": (entry.get("lfs") or {}).get("size") or entry.get("size", 0)
        })

    if not files:
        print(f"  {model_id}: niciun fișier LFS cu SHA256 — manifest neatins")
        skipped += 1
        continue

    # REZUMAT CANONIC — acoperă tot ce poate schimba comportamentul aplicației,
    # nu doar fișierele: un atacator care ar coborî `min_ram_gb` sau ar schimba
    # `model_id` ar păcăli aplicația fără să atingă niciun octet de greutăți.
    # Se folosesc DOAR numere întregi și șiruri: nicio formatare de virgulă
    # mobilă, ca partea Swift să obțină exact aceiași octeți.
    performance = manifest["performance"]
    integration = manifest.get("lexpenal_integration") or {}
    lines = [
        model_id,
        str(int(performance["min_ram_gb"])),
        str(int(performance["context_length_tokens"])),
        str(integration.get("tier", "")),
    ] + [f'{f["path"]}:{f["sha256"]}:{int(f["size_bytes"])}' for f in files]
    digest_source = "\n".join(lines)
    digest = hashlib.sha256(digest_source.encode("utf-8")).hexdigest()

    verification = manifest.setdefault("verification", {})
    verification["files"] = files
    verification["sha256_checksum"] = digest
    verification["checksum_source"] = "huggingface-lfs-oid"
    verification["verification_notes"] = (
        "SHA256 per fișier, preluat din Git LFS de la sursă (lfs.oid ESTE SHA256-ul "
        "conținutului). `sha256_checksum` e rezumatul stabil peste toate fișierele: "
        "se schimbă dacă se schimbă oricare dintre ele. Aplicația verifică FIECARE "
        "fișier în parte — un singur checksum nu poate descrie un model cu mai multe "
        "shard-uri, iar verificarea veche, care compara toate fișierele cu aceeași "
        "valoare, nu putea trece niciodată."
    )
    if not signing_key:
        verification["ed25519_signature"] = ""

    with io.open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    total_gb = sum(f["size_bytes"] for f in files) / 1e9
    print(f"  {model_id}: {len(files)} fișiere, {total_gb:.1f} GB, rezumat {digest[:16]}…")
    updated += 1

print(f"\nmanifeste completate: {updated}, sărite: {skipped}")
PYTHON

if [[ -n "${LEXPENAL_ED25519_PRIVKEY:-}" ]]; then
    echo ""
    echo "Semnare Ed25519 peste rezumatul fiecărui manifest…"
    for manifest in "$SCRIPT_DIR"/mlx-community-*.json; do
        digest=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['verification']['sha256_checksum'])" "$manifest")
        signature=$(printf '%s' "$digest" | openssl pkeyutl -sign \
            -inkey <(printf '%s' "$LEXPENAL_ED25519_PRIVKEY" | xxd -r -p) \
            -rawin 2>/dev/null | base64 | tr -d '\n' || echo "SIGN_FAILED")
        python3 - "$manifest" "$signature" <<'SIGN'
import io, json, sys
path, signature = sys.argv[1], sys.argv[2]
manifest = json.load(open(path))
manifest["verification"]["ed25519_signature"] = signature
with io.open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
SIGN
        echo "  $(basename "$manifest"): semnat"
    done
fi
