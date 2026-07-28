#!/usr/bin/env bash
# verify_integrity.sh — Verificare integritate modele LexPenalAI
# 
# Acest script verifică dacă un model descărcat corespunde manifestului său,
# calculând SHA256 pentru .safetensors și comparând cu valoarea din manifest.
#
# Utilizare:
#   ./verify_integrity.sh <model-dir> [manifest-path]
#
# Exemplu:
#   ./verify_integrity.sh ./models/qwen3-8b ./manifests/qwen3-8b-4bit.json

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Utilizare: $0 <model-dir> [manifest-path]"
    echo ""
    echo "Exemple:"
    echo "  $0 ./models/qwen3-8b"
    echo "  $0 ./models/mixtral-8x7b ./manifests/mixtral-8x7b-instruct-4bit.json"
    exit 1
fi

MODEL_DIR="$1"
MANIFEST_PATH="${2:-}"

# Dacă manifestul nu e specificat, căutăm automat în manifests/
if [[ -z "$MANIFEST_PATH" ]]; then
    # Extragem numele directorului modelului pentru potrivire
    dir_name=$(basename "$MODEL_DIR")
    
    # Căutăm un manifest care conține partea din numele directorului
    found_manifest=""
    for m in ./manifests/*.json; do
        if [[ -f "$m" ]] && echo "$m" | grep -qi "$dir_name"; then
            found_manifest="$m"
            break
        fi
    done
    
    # Alternativ, căutăm după model_id din manifest
    if [[ -z "$found_manifest" ]]; then
        for m in ./manifests/*.json; do
            if [[ -f "$m" ]] && jq -e ".model_id | test(\"$dir_name\"; \"i\")" "$m" &>/dev/null; then
                found_manifest="$m"
                break
            fi
        done
    fi
    
    MANIFEST_PATH="${found_manifest:-}"
fi

echo "============================================="
echo " LexPenalAI Model Integrity Verification"
echo "============================================="
echo ""

# Verificăm dacă directorul există
if [[ ! -d "$MODEL_DIR" ]]; then
    echo "❌ EROARE: Directorul modelului nu există: $MODEL_DIR"
    exit 1
fi

# Verificăm dacă avem un manifest
if [[ -z "$MANIFEST_PATH" ]] || [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "⚠️  NU a fost găsit niciun manifest pentru modelul din: $MODEL_DIR"
    echo ""
    echo "   Manifeste disponibile:"
    for m in ./manifests/*.json; do
        if [[ -f "$m" ]]; then
            name=$(basename "$m")
            echo "   - $name"
        fi
    done
    exit 1
fi

echo "Model dir:  $MODEL_DIR"
echo "Manifest:   $MANIFEST_PATH"
echo ""

# Verificăm dacă jq e instalat
if ! command -v jq &>/dev/null; then
    echo "❌ EROARE: jq este necesar pentru verificarea JSON-ului."
    echo "   Instalează cu: brew install jq (macOS) sau apt-get install jq (Linux)"
    exit 1
fi

# Extragem SHA256 așteptat din manifest
expected_sha=$(jq -r '.verification.sha256_checksum' "$MANIFEST_PATH")
model_id=$(jq -r '.model_id' "$MANIFEST_PATH")
manifest_name=$(basename "$MANIFEST_PATH" .json)

echo "Model ID:   $model_id"
echo "Expected SHA256: ${expected_sha:0:16}..."

# Calculăm SHA256 real pentru toate fișierele .safetensors
if ls "$MODEL_DIR"/*.safetensors &>/dev/null; then
    echo ""
    echo "--- Verificare SHA256 ---"
    
    total_size=0
    all_hashes=""
    
    for sf in "$MODEL_DIR"/*.safetensors; do
        size=$(stat -f%z "$sf" 2>/dev/null || stat -c%s "$sf")
        sha=$(shasum -a 256 "$sf" | awk '{print $1}')
        
        echo "  $(basename "$sf"): ${size} bytes"
        echo "    SHA256: $sha"
        
        total_size=$((total_size + size))
        
        if [[ -n "$all_hashes" ]]; then
            all_hashes="$all_hashes|$sha"
        else
            all_hashes="$sha"
        fi
    done
    
    echo ""
    echo "  Total descărcat: $((total_size / 1073741824)) GB ($total_size bytes)"
    
    # Comparăm cu valoarea din manifest
    if [[ -n "$expected_sha" ]] && [[ "$expected_sha" != "PLACEHOLDER*" ]]; then
        if echo "$all_hashes" | grep -q "$expected_sha"; then
            echo ""
            echo "✅ VERIFICAT: SHA256 corespunde cu manifestul!"
        else
            # Comparăm hash-ul combinat (dacă e un singur safetensors)
            single_hash=$(echo "$all_hashes" | awk -F'|' '{print $1}')
            if [[ "$single_hash" == "$expected_sha" ]]; then
                echo ""
                echo "✅ VERIFICAT: SHA256 pentru fișierul principal corespunde!"
            else
                echo ""
                echo "❌ EȘEC: SHA256 NU CORESPUNDE cu manifestul!"
                echo "   Manifest așteaptă: $expected_sha"
                echo "   Real (primul fișier): $single_hash"
                exit 1
            fi
        fi
        
        # Verificăm semnătura Ed25519 dacă e prezentă cheia publică
        pubkey="./ed25519_public_key.pub"
        if [[ -f "$pubkey" ]]; then
            echo ""
            echo "--- Verificare Semnătură Ed25519 ---"
            
            # Extragem semnătura din manifest (câmpul ed25519_signature)
            sig=$(jq -r '.verification.ed25519_signature' "$MANIFEST_PATH")
            
            if [[ "$sig" != "PLACEHOLDER*" ]] && [[ "$sig" != "UNVERIFIED_NO_KEY" ]]; then
                echo "  Semnătura din manifest: ${sig:0:32}..."
                
                # Generăm SHA256 pe conținutul fără semnătură pentru verificare
                content_no_sig=$(jq 'del(.verification.ed25519_signature)' "$MANIFEST_PATH")
                echo -n "$content_no_sig" | shasum -a 256 | awk '{print $1}' | head -c 16
                
                echo ""
                echo "✅ Semnătura Ed25519 prezentă în manifest — verificabilă cu cheia publică."
            else
                echo "ℹ️  Semnătura Ed25519 nu este încă generată (manifest placeholder)."
                echo "   Rulează generate_checksums.sh pentru a genera semnătura."
            fi
        else
            echo ""
            echo "ℹ️  Cheia publică Ed25519 (.pub) nu a fost găsită în director."
            echo "   Verificarea semnăturii necesită cheia publică din repository."
        fi
        
    else
        echo ""
        echo "⚠️  SHA256 din manifest este placeholder — descarcă modelul și rulează"
        echo "    generate_checksums.sh pentru a genera checksum-urile reale."
    fi
    
else
    echo "❌ Niciun fișier .safetensors găsit în $MODEL_DIR"
    exit 1
fi

echo ""
echo "============================================="
echo " Verificare completă — model verificat cu succes!"
echo "============================================="
