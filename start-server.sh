#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MODEL_DIR="$SCRIPT_DIR/models"
SOURCE_DIR="${LLAMA_CPP_SOURCE_DIR:-$HOME/llama.cpp}"
BUILD_DIR="${LLAMA_CPP_BUILD_DIR:-$SOURCE_DIR/build-gb10}"
SERVER="$BUILD_DIR/bin/llama-server"

usage() {
  printf 'Usage: %s [fichier.gguf|chemin/vers/fichier.gguf] [options llama-server...]\n' "$0"
  printf 'Sans fichier, sélectionne automatiquement le seul GGUF présent ou demande lequel lancer.\n'
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x "$SERVER" ]]; then
  printf 'Erreur : llama-server est introuvable ou non exécutable : %s\n' "$SERVER" >&2
  printf 'Compile-le avec %s/update.sh, puis réessaie.\n' "$SCRIPT_DIR" >&2
  exit 1
fi

shopt -s nullglob
models=("$MODEL_DIR"/*.gguf)
shopt -u nullglob

if (($# > 0)); then
  requested_model="$1"
  shift
  if [[ -f "$requested_model" ]]; then
    model="$(realpath -- "$requested_model")"
  elif [[ -f "$MODEL_DIR/$requested_model" ]]; then
    model="$MODEL_DIR/$requested_model"
  else
    printf 'Erreur : modèle introuvable : %s\n' "$requested_model" >&2
    printf 'Dépose le fichier dans %s ou indique son chemin complet.\n' "$MODEL_DIR" >&2
    exit 1
  fi
elif ((${#models[@]} == 0)); then
  printf 'Aucun fichier .gguf trouvé dans : %s\n' "$MODEL_DIR" >&2
  printf 'Dépose un modèle GGUF dans ce dossier, puis relance ce script.\n' >&2
  exit 1
elif ((${#models[@]} == 1)); then
  model="${models[0]}"
else
  printf 'Modèles disponibles :\n'
  for i in "${!models[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${models[$i]##*/}"
  done
  read -r -p 'Numéro du modèle à lancer : ' choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#models[@]})); then
    printf 'Erreur : sélection invalide.\n' >&2
    exit 1
  fi
  model="${models[$((choice - 1))]}"
fi

host="${LLAMA_HOST:-127.0.0.1}"
port="${LLAMA_PORT:-8080}"
gpu_layers="${LLAMA_GPU_LAYERS:-99}"
ctx_size="${LLAMA_CTX_SIZE:-8192}"

printf 'Modèle : %s\n' "$model"
printf 'API : http://%s:%s/v1\n' "$host" "$port"
exec "$SERVER" -m "$model" --host "$host" --port "$port" \
  -ngl "$gpu_layers" -c "$ctx_size" "$@"
