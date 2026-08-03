# LexPenalAI Model Repository

**Repository oficial pentru modelele locale LexPenalAI — "Copilot juridic penal pentru avocați"**

Acest repository conține manifeste JSON semnate cu modele de securitate (SHA256 + Ed25519) pentru toate modelele locale disponibile în aplicația LexPenalAI. Fiecare model este verificat la descărcare împotriva manifestului corespunzător.

---

## 📁 Convenția de nume a manifestelor

Aplicația LexPenalAI cere manifestul fiecărui model la URL-ul:

```
https://raw.githubusercontent.com/raresmihailcristea-cmyk/lexpenal-models/main/<model_id cu "/" înlocuit prin "-">.json
```

Exemple: `mlx-community-Qwen3-8B-4bit.json`, `microsoft-Phi-3-mini-4k-instruct-4bit.json`.
Toate cele 12 modele din catalog (10 principale + 2 worker) au manifest sub această convenție.
Fișierele istorice cu nume scurt (`phi-3-mini-4k-instruct-4bit.json` etc.) rămân pentru compatibilitate.

### Roluri diferite de manifest
- **Manifestele MLX** (`mlx-community-*.json`, `microsoft-*.json`) — metadate + verificare de
  integritate (schema `schemas/model-manifest-v1.json`). Greutățile modelelor se descarcă din
  Hugging Face Hub prin runtime-ul MLX al aplicației.
- **`qwen3-4b-q4.manifest.json`** — manifest de DESCĂRCARE pentru modelul Core ML de rezervă:
  listă completă de fișiere cu URL-uri (GitHub Releases) și SHA256 per fișier, consumată direct
  de descărcătorul aplicației.

### Stadiul verificării
Câmpurile `verification.sha256_checksum` și `verification.ed25519_signature` sunt goale
(= „neverificat încă") până când:
1. `generate_checksums.sh` calculează SHA256 pe greutățile descărcate;
2. manifestul este semnat Ed25519 cu cheia privată a proiectului (Secret Manager backend).

Aplicația tratează câmpurile goale ca „integritate neverificată" (avertisment), nu ca eroare.
Valorile de exemplu/placeholder au fost eliminate intenționat: un checksum fals este mai
periculos decât unul absent.

¹ Ministral-8B și Mistral Large sunt sub Mistral Research License — utilizarea comercială
necesită acord separat cu Mistral AI.

---

## 📋 Lista Modelelor Disponibile

| # | Model | Parametri | RAM Min | Dimensiune | Context | Licență |
|---|-------|-----------|---------|------------|---------|---------|
| 1 | **Phi-3 Mini 4K (4-bit)** | 3.8B | 8 GB | 2.3 GB | 4K tokeni | MIT |
| 2 | **Qwen3-4B (4-bit)** ⭐ | 4B | 8 GB | 2.4 GB | 32K tokeni | Apache 2.0 |
| 3 | **Qwen3-8B (4-bit)** 🔥 | 8B | 16 GB | 4.6 GB | 32K tokeni | Apache 2.0 |
| 4 | **Ministral-8B (4-bit)** | 8B | 16 GB | 4.6 GB | 32K tokeni | Mistral Research License¹ |
| 5 | **Qwen3-14B (4-bit)** | 14B | 32 GB | 8.2 GB | 32K tokeni | Apache 2.0 |
| 6 | **Qwen3-32B (4-bit)** | 32B | 32 GB | 18 GB | 32K tokeni | Apache 2.0 |
| 7 | **Mixtral 8x7B MoE (4-bit)** 🆕 | 46.7B (12.9B activi) | 64 GB | 26 GB | 32K tokeni | Apache 2.0 |
| 8 | **Llama 3.3 70B (4-bit)** | 70B | 64 GB | 40 GB | 128K tokeni | Meta Community License |
| 9 | **Llama 3.1 405B Q4** 🆕 | 405B | 128 GB | 60 GB | 128K tokeni | Meta Community License |
| 10 | **Mistral Large 123B (4-bit)** | 123B | 128 GB | 69 GB | 128K tokeni | Mistral AI Research |

**Legendă:** ⭐ = model implicit pe dispozitive 8 GB; 🔥 = recomandat pentru analiză juridică

### Modele Worker (doar 32 GB+ RAM)
| Model | Parametri | Dimensiune | Utilizare |
|-------|-----------|------------|-----------|
| Qwen3-1.7B (worker) | 1.7B | 1.1 GB | Clasificare, rezumate scurte, triere fundal |
| Qwen3-0.6B (ultra-light) | 0.6B | 0.5 GB | Etichetare/triere rapidă, impact minim RAM |

---

## 🔐 Securitate și Verificare

### Verificarea Integrității

Fiecare model este însoțit de un manifest JSON care conține:
- **SHA256 checksum** — garantă că fișierul descărcat nu a fost modificat
- **Semnătură Ed25519** — garantează autenticitatea sursei (semnat cu cheia privată a proiectului)

### Cum se verifică un model descărcat:

```bash
# 1. Descarcă modelul
huggingface-cli download mlx-community/Qwen3-8B-4bit --local-dir ./models/qwen3-8b

# 2. Verifică SHA256
cd models/qwen3-8b
sha256sum *.safetensors > checksums.txt
cat checksums.txt

# 3. Compară cu manifestul din repository
# (conținutul câmpului 'verification.sha256_checksum' din manifests/*.json)

# 4. Verifică semnătura Ed25519 (dacă cheia publică e disponibilă)
openssl pkeyutl -verify -pubin -inkey ed25519_public_key.der \
    -rawin -pkeyopt digest:sha256 \
    -in manifest.json \
    -sigfile manifest.json.sig
```

### Generarea automată a checksum-urilor și semnăturilor:

```bash
# Din directorul manifests/
export LEXPENAL_ED25519_PRIVKEY=<hex-chiava-privata>
./generate_checksums.sh --model-dir ./models/qwen3-8b
```

---

## 📁 Structura Repository

```
lexpenal-models/
├── README.md                           ← Acest fișier
├── schemas/                            ← Schema JSON pentru manifeste
│   └── model-manifest-v1.json          ← JSON Schema Draft-07
├── manifests/                          ← Manifeste semnate (unul per model)
│   ├── phi-3-mini-4k-instruct-4bit.json
│   ├── qwen3-4b-4bit.json              ← Model implicit 8 GB
│   ├── qwen3-8b-4bit.json              ← Recomandat analiză juridică
│   ├── ministral-8b-instruct-2410-4bit.json
│   ├── qwen3-14b-4bit.json
│   ├── qwen3-32b-4bit.json
│   ├── mixtral-8x7b-instruct-4bit.json 🆕
│   ├── llama-3.3-70b-instruct-4bit.json
│   └── llama-3.1-405b-instruct-q4.json 🆕
├── ed25519_public_key.pub              ← Cheia publică pentru verificare (commitată)
└── verify.sh                           ← Script de verificare rapidă
```

---

## 🔑 Licențe Modele

### Open Source (utilizare liberă, comercială permisă)
| Model | Licență | Note |
|-------|---------|------|
| Phi-3 Mini 4K | MIT | Microsoft Research — utilizare comercială și modificare permise |
| Qwen3 series (4B/8B/14B/32B) | Apache 2.0 | Alibaba — utilizare comercială, modificare, redistribuire permise |
| Ministral-8B | Apache 2.0 | Mistral AI — licență open-source standard |

### Restrictions (utilizare limitată)
| Model | Licență | Restricții |
|-------|---------|------------|
| Mixtral 8x7B MoE | Apache 2.0 + Mistral Research | Utilizare comercială permisă; variantă quantizată de mlx-community |
| Llama 3.3 70B | Meta Community License | Permisă utilizare comercială și academică; redistribuirea modelului brut necesită aprobare Meta |
| Llama 3.1 405B | Meta Community License | **Nu poate fi redistribuit**; doar utilizare locală pe dispozitivul proprietar |
| Mistral Large 123B | Mistral AI Research | Cercetare și utilizare personală; utilizare comercială necesită licență separată |

---

## 📥 Descărcarea Modelelor

### Cerințe preliminare:
```bash
# Instalează Hugging Face Hub CLI
pip install -U "huggingface_hub[cli]"

# Autentifică-te (necesitar pentru modele restricționate ca Llama)
huggingface-cli login
```

### Comenzi rapide de descărcare:

```bash
# Model implicit 8 GB (iPhone/iPad)
huggingface-cli download mlx-community/Qwen3-4B-4bit --local-dir ./qwen3-4b

# Recomandat pentru analiză juridică (iPad Pro M-series / Mac)
huggingface-cli download mlx-community/Qwen3-8B-4bit --local-dir ./qwen3-8b

# Phi-3 Mini 4K (triire rapida, worker)
huggingface-cli download microsoft/Phi-3-mini-4k-instruct --revision main --local-dir ./phi-3-mini

# Mixtral 8x7B MoE (64 GB RAM — Mac Studio/Pro)
huggingface-cli download mlx-community/Mixtral-8x7B-Instruct-4bit --local-dir ./mixtral-8x7b

# Llama 3.1 405B Q4 (128+ GB RAM — Mac Studio Max / Mac Pro)
huggingface-cli download mlx-community/Llama-3.1-405B-Instruct-Q4 --local-dir ./llama-3.1-405b

# Ministral-8B (alternativă Qwen pe limbi latine)
huggingface-cli download mlx-community/Ministral-8B-Instruct-2410-4bit --local-dir ./ministral-8b
```

### Verificare post-descărcare:
```bash
# Calculează SHA256 pentru toate fișierele modelului
cd ./qwen3-8b
shasum -a 256 *.safetensors | awk '{print $1}' | paste -sd, -

# Compară cu valoarea din manifest (câmpul verification.sha256_checksum)
```

---

## 🏗️ Integrare cu LexPenalAI

### Cum funcționează verificarea în aplicație:

1. **La instalare:** `ModelDownloadService` verifică RAM-ul dispozitivului
2. **Recomandare:** Alege modelul corespunzător (`LexLocalModelCatalog.recommended(ramGB:)`)
3. **Descărcare:** Descarcă modelul din Hugging Face (o singură dată, cache local)
4. **Verificare:** Calculează SHA256 și compară cu manifestul semnătura Ed25519
5. **Încărcare:** Modelul e încărcat în MLX Swift runtime prin `LexMLXLLMService`

### Cod relevant în proiect:
- `Services/LexMLXLLMService.swift` — catalog modele + runtime MLX
- `Services/LocalModelManagement.swift` — descărcare, verificare integritate
- `Models/AllModelTypes.swift` — tipuri de date pentru UI

---

## 📝 Contribuții

Pentru a adăuga un model nou:

1. Creează manifestul JSON conform schimei din `schemas/model-manifest-v1.json`
2. Calculează SHA256 pentru fișierele .safetensors descărcate
3. Semnează cu cheia Ed25519 privată a proiectului
4. Adaugă intrarea în catalogul Swift (`LexLocalModelCatalog.all`)
5. Trimite PR către acest repository

### Generare manifest nou:
```bash
# Copiază un manifest existent ca template
cp manifests/qwen3-8b-4bit.json manifests/noul-model.json

# Editează câmpurile necesare
jq '.model_id = "repo/noul-model"' manifests/noul-model.json > /tmp/tmp.json && mv /tmp/tmp.json manifests/noul-model.json

# Verifică conformitatea cu schema
jq empty manifests/noul-model.json  # verifică JSON valid
```

---

## 🔒 Cheia Publică Ed25519

Pentru a verifica semnăturile manifestelor, folosește cheia publică din `ed25519_public_key.pub`:

```bash
# Verificare manuală
openssl pkeyutl -verify -pubin \
    -inkey ed25519_public_key.der \
    -rawin -pkeyopt digest:sha256 \
    -in manifest.json.sig \
    -sigfile manifest.json.sig
```

---

## 📄 Licența acestui Repository

Acest repository (manifeste și documentație) este publicat sub **Apache License 2.0**.

Modelele de machine learning listate își păstrează licențele individuale — vezi secțiunea [Licențe Modele](#-licențe-modele) mai sus.

---

**Menționare:** Acest repository facе parte din proiectul LexPenalAI — "Copilot juridic penal pentru avocați", dezvoltat de raremihailcristea-cmyk.
