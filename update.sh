#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="${LLAMA_CPP_SOURCE_DIR:-$HOME/llama.cpp}"
BUILD_DIR="${LLAMA_CPP_BUILD_DIR:-$SOURCE_DIR/build-gb10}"
CUDA_COMPILER="${CMAKE_CUDA_COMPILER:-/usr/local/cuda/bin/nvcc}"
BUILD_MARKER="$BUILD_DIR/.llama-cpp-built-commit"

if [[ ! -e "$SOURCE_DIR/.git" ]]; then
  printf 'Erreur : dépôt llama.cpp introuvable dans %s\n' "$SOURCE_DIR" >&2
  exit 1
fi

if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain --untracked-files=no)" ]]; then
  printf 'Erreur : le dépôt contient des modifications locales suivies par Git.\n' >&2
  printf 'Sauvegarde-les ou annule-les avant la mise à jour ; rien n’a été modifié.\n' >&2
  exit 1
fi

before="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
printf 'Vérification des mises à jour llama.cpp...\n'
if ! git -C "$SOURCE_DIR" pull --ff-only; then
  printf 'Erreur : git pull a échoué. Vérifie la branche, le réseau et les changements locaux.\n' >&2
  exit 1
fi
after="$(git -C "$SOURCE_DIR" rev-parse HEAD)"

built_commit=''
if [[ -r "$BUILD_MARKER" ]]; then
  IFS= read -r built_commit < "$BUILD_MARKER" || true
fi

if [[ "$after" == "$built_commit" \
  && -x "$BUILD_DIR/bin/llama-cli" \
  && -x "$BUILD_DIR/bin/llama-server" ]]; then
  printf 'llama.cpp est à jour ; aucun rebuild nécessaire.\n'
  exit 0
fi

if [[ "$before" != "$after" ]]; then
  printf 'Le code a été mis à jour ; reconfiguration et compilation...\n'
else
  printf 'Le build est absent ou ne correspond pas au code ; compilation...\n'
fi

if [[ ! -x "$CUDA_COMPILER" ]]; then
  printf 'Erreur : compilateur CUDA introuvable ou non exécutable : %s\n' "$CUDA_COMPILER" >&2
  exit 1
fi

export PATH="$(dirname -- "$CUDA_COMPILER"):$PATH"
export CUDACXX="$CUDA_COMPILER"

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -DCMAKE_CUDA_COMPILER="$CUDA_COMPILER" \
  -DGGML_NATIVE=ON \
  -DGGML_CUDA=ON \
  -DGGML_CURL=ON \
  -DCMAKE_CUDA_ARCHITECTURES=121a-real

cmake --build "$BUILD_DIR" --config Release \
  --target llama-cli llama-server -j 8

printf '%s\n' "$after" > "$BUILD_MARKER"
printf 'Build terminé ; llama-cli et llama-server sont à jour.\n'
