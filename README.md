# Outils llama.cpp locaux

Ce dossier contient les scripts de lancement et de mise à jour pour le clone
`~/llama.cpp`. Les modèles GGUF à utiliser sont à placer directement dans
`models/`.

## Installer sur un GB10

Sur un GB10 neuf, lance l'installateur sans `sudo` :

```bash
cd ~/Documents/llama.cpp-tools-GB10
./install.sh
```

Il installe les dépendances système avec `sudo`, vérifie le GPU et cherche
`nvcc` dans `/usr/local/cuda/bin`, `/usr/local/cuda-*/bin` et le `PATH`.
Il passe explicitement le chemin de `nvcc` à CMake pour éviter l'erreur
`No CMAKE_CUDA_COMPILER could be found`, puis clone ou met à jour llama.cpp,
compile pour sm_121 et enregistre le commit compilé. Il ne télécharge pas de
modèle GGUF. Le pilote NVIDIA et CUDA Toolkit doivent déjà être installés ;
l’installateur ne les installe pas et s’arrête avec une erreur explicite si
`nvcc` est introuvable.

## Lancer le serveur

Depuis un terminal :

```bash
cd ~/Documents/llama.cpp-tools-GB10
./start-server.sh
```

Le script lance automatiquement le seul fichier `.gguf` trouvé. S'il y en a
plusieurs, il demande lequel utiliser. On peut aussi choisir directement un
fichier :

```bash
./start-server.sh mon-modele.gguf
```

Le serveur écoute par défaut sur `http://127.0.0.1:8080/v1`. Il reste local à
la machine. Les valeurs par défaut peuvent être ajustées avec `LLAMA_HOST`,
`LLAMA_PORT`, `LLAMA_GPU_LAYERS` et `LLAMA_CTX_SIZE`.

## Utiliser PaddleOCR-VL-1.6

PaddleOCR-VL-1.6 a besoin du GGUF du modèle et du fichier de vision `mmproj`.
Place les deux dans `models/` et utilise un `mmproj` compatible avec la version
et la quantification du modèle. Par exemple, avec
`PaddleOCR-VL-1.6.Q8_0.gguf` et `PaddleOCR-VL-1.6-mmproj.gguf`, lance l’OCR
d’une image ainsi :

```bash
cd ~/Documents/llama.cpp-tools-GB10
"$HOME/llama.cpp/build-gb10/bin/llama-cli" \
  -m "$PWD/models/PaddleOCR-VL-1.6.Q8_0.gguf" \
  --mmproj "$PWD/models/PaddleOCR-VL-1.6-mmproj.gguf" \
  --image "$PWD/document.png" \
  -p "OCR:" \
  -n 4096
```

Pour démarrer le serveur avec ce modèle, passe aussi le chemin du `mmproj` :

```bash
./start-server.sh PaddleOCR-VL-1.6.Q8_0.gguf \
  --mmproj "$PWD/models/PaddleOCR-VL-1.6-mmproj.gguf" --temp 0
```

Le nom du fichier `mmproj` peut varier : adapte le chemin à celui que tu as
téléchargé. Pour l’API du serveur, envoie l’image avec le prompt `OCR:`.

## Mettre llama.cpp à jour

```bash
cd ~/Documents/llama.cpp-tools-GB10
./update.sh
```

Le script fait un `git pull --ff-only`. Il ne recompile que si le code a changé
ou si les exécutables/le marqueur de build manquent. Il utilise
`~/llama.cpp/build-gb10` et compile pour le GB10 avec CUDA.
