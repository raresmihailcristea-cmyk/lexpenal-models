#!/usr/bin/env bash
# generate_checksums.sh — LexPenalAI Model Manifest Verification Tool
# 
# Acest script calculează SHA256 pentru fișierele modelului și generează
# semnături Ed25519 (prin OpenSSL) pentru fiecare manifest.
# 
# Utilizare:
#   ./generate_checksums.sh --model-dir <path-to-downloaded-model>
#
# Exemplu:
#   ./generate_checksums.sh --model-dir ./models/phi-3-mini-4k

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$SCRIPT_DIR"
ED25519_PRIVATE_KEY="${LEXPENAL_ED25519_PRIVKEY:-}"

# Verificare precondiții
if [[ -z "$ED25519_PRIVATE_KEY" ]]; then
    echo "⚠️  AVERTISMENT: Variabila LEXPENAL_ED25519_PRIVKEY nu este setată."
    echo "   Semnăturile Ed25519 NU vor fi generate (doar SHA256 checksums)."
    echo ""
    echo "   Pentru a genera semnături, setează cheia privată:"
    echo "   export LEXPENAL_ED25519_PRIVKEY=<hex-chiava-privata>"
    echo ""
fi

# Funcție: calculează SHA256 pentru un fișier
calc_sha256() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        sha256sum "$file" | awk '{print $1}'
    fi
}

# Funcție: semnează un string cu Ed25519 (OpenSSL)
sign_ed25519() {
    local data="$1"
    if [[ -n "$ED25519_PRIVATE_KEY" ]]; then
        echo -n "$data" | openssl pkeyutl -sign \
            -inkey <(echo "$ED25519_PRIVATE_KEY" | xxd -r -p) \
            -padding raw 2>/dev/null | base64 -w 0 || echo "SIGN_FAILED"
    else
        echo "UNVERIFIED_NO_KEY"
    fi
}

# Funcție: actualizează un câmp într-un JSON (folosind jq)
update_json_field() {
    local file="$1"
    local field="$2"
    local value="$3"
    
    if command -v jq &>/dev/null; then
        local tmp=$(mktemp)
        jq --arg val "$value" ".[\"$field\"] = \$val" "$file" > "$tmp" && mv "$tmp" "$file"
    else
        echo "⚠️  jq nu este instalat — actualizare manuală necesară"
        return 1
    fi
}

echo "============================================="
echo " LexPenalAI Model Manifest Verification Tool"
echo "============================================="
echo ""

# Parcurgem toate manifestele din directorul manifests/
manifest_count=0
for manifest in "$MANIFEST_DIR"/*.json; do
    [[ -f "$manifest" ]] || continue
    
    filename=$(basename "$manifest")
    echo "--- Procesare: $filename ---"
    
    # Extragem model_id-ul din JSON
    if command -v jq &>/dev/null; then
        model_id=$(jq -r '.model_id' "$manifest")
        echo "  Model ID: $model_id"
        
        # Verificăm dacă există fișiere .safetensors în model-dir
        if [[ -n "${MODEL_DIR:-}" ]]; then
            safetensor_files=("$MODEL_DIR"/*.safetensors)
            if [[ ${#safetensor_files[@]} -gt 0 ]]; then
                echo "  Verificare integritate fișiere..."
                total_size=0
                for sf in "${safetensor_files[@]}"; do
                    size=$(stat -f%z "$sf" 2>/dev/null || stat -c%s "$sf")
                    sha=$(calc_sha256 "$sf")
                    echo "    $(basename "$sf"): ${size} bytes | SHA256: $sha"
                    total_size=$((total_size + size))
                done
                echo "  Total: $((total_size / 1073741824)) GB"
                
                # Generăm checksum combinat pentru toate safetensors
                combined_sha=$(cat "${safetensor_files[@]}" | shasum -a 256 | awk '{print $1}')
                echo "  Combined SHA256: $combined_sha"
                
                # Actualizăm câmpul sha256_checksum în manifest
                update_json_field "$manifest" "sha256_checksum" "$combined_sha"
            else
                echo "  ⚠️  Niciun fișier .safetensors găsit în $MODEL_DIR"
                echo "     Descarcă modelul mai întâi cu: huggingface-cli download ..."
            fi
        fi
        
        # Generăm semnătura Ed25519 pe conținutul manifestului (fără câmpul de semnătură)
        if [[ -n "$ED25519_PRIVATE_KEY" ]]; then
            # Eliminăm temporal câmpul de semnătură pentru a semna restul
            content_no_sig=$(jq 'del(.verification.ed25519_signature)' "$manifest")
            signature=$(echo -n "$content_no_sig" | openssl pkeyutl -sign \
                -inkey <(echo "$ED25519_PRIVATE_KEY" | xxd -r -p) \
                -padding raw 2>/dev/null | base64 -w 0 || echo "SIGN_FAILED")
            
            if [[ "$signature" != "SIGN_FAILED" ]]; then
                update_json_field "$manifest" "ed25519_signature" "$signature"
                # Actualizăm și timestamp-ul de verificare
                update_json_field "$manifest" "verified_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
                echo "  ✓ Semnătură Ed25519 generată și aplicată"
            else
                echo "  ⚠️  Eroare la semnarea Ed25519"
            fi
        else
            echo "  ℹ️  Skipped Ed25519 (nu este setată cheia privată)"
        fi
        
    else
        echo "  ⚠️  jq necesar pentru parsare JSON — instalează cu: brew install jq"
    fi
    
    manifest_count=$((manifest_count + 1))
    echo ""
done

echo "============================================="
echo " Rezumat: $manifest_count manifest(e) procesat(e)"
echo "============================================="

if [[ -n "$ED25519_PRIVATE_KEY" ]]; then
    # Generăm cheia publică din cea privată pentru verificare ulterioară
    pubkey_file="$MANIFEST_DIR/ed25519_public_key.pub"
    if [[ ! -f "$pubkey_file" ]] || ! grep -q "PUBLIC" "$pubkey_file" 2>/dev/null; then
        openssl pkey -in <(echo "$ED25519_PRIVATE_KEY" | xxd -r -p) \
            -pubout -outform DER 2>/dev/null > "${pubkey_file}.der" || true
        echo ""
        echo "ℹ️  Cheia publică Ed25519 (pentru verificare) necesită extragere separată."
    fi
fi

echo ""
echo "Manifestele sunt gata pentru commit în repository-ul lexpenal-models."
echo "SHA256 checksum-urile vor fi actualizate automat la descărcarea efectivă a modelelor."
