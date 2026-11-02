#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_DIR="${LLAMA_CPP_SOURCE_DIR:-$HOME/llama.cpp}"
BUILD_DIR="${LLAMA_CPP_BUILD_DIR:-$SOURCE_DIR/build-gb10}"
CUDA_COMPILER="${CMAKE_CUDA_COMPILER:-}"
BUILD_JOBS="${LLAMA_BUILD_JOBS:-8}"
REPOSITORY_URL="https://github.com/ggml-org/llama.cpp"

usage() {
  printf 'Usage: %s\n' "$0"
  printf 'Installe les dépendances, récupère llama.cpp et compile llama-cli/llama-server pour le GB10.\n'
  printf 'La compilation utilise %s par défaut ; le nombre de tâches peut être changé avec LLAMA_BUILD_JOBS.\n' "$BUILD_DIR"
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
  exit 0
fi

if ((EUID == 0)); then
  printf 'Erreur : lance ce script sans sudo ; il demandera sudo uniquement pour les paquets système.\n' >&2
  exit 1
fi

if [[ "$(uname -m)" != "aarch64" ]]; then
  printf 'Erreur : cet installateur cible le GB10 ARM64 ; architecture détectée : %s\n' "$(uname -m)" >&2
  exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  printf 'Erreur : nvidia-smi est introuvable. Vérifie que le pilote NVIDIA du système est installé.\n' >&2
  exit 1
fi

if ! gpu_names="$(nvidia-smi --query-gpu=name --format=csv,noheader)"; then
  printf 'Erreur : impossible d’interroger le GPU avec nvidia-smi.\n' >&2
  exit 1
fi
if [[ "$gpu_names" != *GB10* ]]; then
  printf 'Erreur : ce script cible un NVIDIA GB10 ; GPU détecté : %s\n' "$gpu_names" >&2
  exit 1
fi
printf 'GPU détecté : %s\n' "$gpu_names"

if ! command -v sudo >/dev/null 2>&1; then
  printf 'Erreur : sudo est requis pour installer les dépendances système.\n' >&2
  exit 1
fi

printf 'Installation des dépendances système...\n'
sudo apt-get update
sudo apt-get install -y git clang cmake libcurl4-openssl-dev libssl-dev

if [[ -z "$CUDA_COMPILER" ]]; then
  if [[ -x /usr/local/cuda/bin/nvcc ]]; then
    CUDA_COMPILER="/usr/local/cuda/bin/nvcc"
  else
    for candidate in /usr/local/cuda-*/bin/nvcc; do
      if [[ -x "$candidate" ]]; then
        CUDA_COMPILER="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$CUDA_COMPILER" ]]; then
    CUDA_COMPILER="$(command -v nvcc || true)"
  fi
fi

if [[ -n "$CUDA_COMPILER" && ! -x "$CUDA_COMPILER" ]]; then
  resolved_compiler="$(command -v "$CUDA_COMPILER" || true)"
  if [[ -n "$resolved_compiler" ]]; then
    CUDA_COMPILER="$resolved_compiler"
  fi
fi

if [[ -z "$CUDA_COMPILER" || ! -x "$CUDA_COMPILER" ]]; then
  printf 'Erreur : nvcc est introuvable.\n' >&2
  printf 'CUDA Toolkit doit être installé ; chemins vérifiés : /usr/local/cuda/bin, /usr/local/cuda-*/bin et PATH.\n' >&2
  printf 'Le pilote seul ne fournit pas nvcc. Vérifie l’installation CUDA du GB10, puis relance ce script.\n' >&2
  exit 1
fi

CUDA_COMPILER="$(realpath -- "$CUDA_COMPILER")"
CUDA_ROOT="$(cd -- "$(dirname -- "$CUDA_COMPILER")/.." && pwd -P)"
export PATH="$(dirname -- "$CUDA_COMPILER"):$PATH"
export CUDACXX="$CUDA_COMPILER"

printf 'Compilateur CUDA utilisé : %s\n' "$CUDA_COMPILER"
nvcc --version

if [[ -e "$SOURCE_DIR" ]]; then
  if [[ ! -e "$SOURCE_DIR/.git" ]]; then
    printf 'Erreur : %s existe mais n’est pas un dépôt Git ; rien n’a été écrasé.\n' "$SOURCE_DIR" >&2
    exit 1
  fi

  if ! origin_url="$(git -C "$SOURCE_DIR" remote get-url origin)"; then
    printf 'Erreur : impossible de lire le dépôt distant origin de %s.\n' "$SOURCE_DIR" >&2
    exit 1
  fi
  case "$origin_url" in
    https://github.com/ggml-org/llama.cpp|https://github.com/ggml-org/llama.cpp.git|git@github.com:ggml-org/llama.cpp.git|ssh://git@github.com/ggml-org/llama.cpp.git)
      ;;
    *)
      printf 'Erreur : origin de %s n’est pas le dépôt officiel ggml-org/llama.cpp : %s\n' "$SOURCE_DIR" "$origin_url" >&2
      exit 1
      ;;
  esac

  if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain --untracked-files=no)" ]]; then
    printf 'Erreur : le dépôt contient des modifications locales suivies par Git.\n' >&2
    printf 'Sauvegarde-les ou annule-les avant l’installation ; elles ne seront pas écrasées.\n' >&2
    exit 1
  fi

  printf 'Mise à jour du dépôt llama.cpp existant...\n'
  if ! git -C "$SOURCE_DIR" pull --ff-only; then
    printf 'Erreur : git pull a échoué. Vérifie la branche, le réseau et les changements locaux.\n' >&2
    exit 1
  fi
else
  printf 'Clonage de llama.cpp dans %s...\n' "$SOURCE_DIR"
  mkdir -p -- "$(dirname -- "$SOURCE_DIR")"
  git clone "$REPOSITORY_URL" "$SOURCE_DIR"
fi

if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Erreur : LLAMA_BUILD_JOBS doit être un entier positif ; reçu : %s\n' "$BUILD_JOBS" >&2
  exit 1
fi

mkdir -p -- "$SCRIPT_DIR/models"
printf 'Configuration CUDA pour sm_121...\n'
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -DCMAKE_CUDA_COMPILER="$CUDA_COMPILER" \
  -DCUDAToolkit_ROOT="$CUDA_ROOT" \
  -DGGML_NATIVE=ON \
  -DGGML_CUDA=ON \
  -DGGML_CURL=ON \
  -DCMAKE_CUDA_ARCHITECTURES=121a-real

printf 'Compilation de llama-cli et llama-server...\n'
cmake --build "$BUILD_DIR" --config Release \
  --target llama-cli llama-server -j "$BUILD_JOBS"

git -C "$SOURCE_DIR" rev-parse HEAD > "$BUILD_DIR/.llama-cpp-built-commit"
printf 'Installation terminée.\n'
printf 'llama-server : %s/bin/llama-server\n' "$BUILD_DIR"
printf 'llama-cli    : %s/bin/llama-cli\n' "$BUILD_DIR"
printf 'Dépose tes modèles .gguf dans : %s/models\n' "$SCRIPT_DIR"
printf 'Lance le serveur avec : %s/start-server.sh\n' "$SCRIPT_DIR"
