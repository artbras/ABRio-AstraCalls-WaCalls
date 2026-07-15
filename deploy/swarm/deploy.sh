#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy/swarm"
ENV_FILE="${ENV_FILE:-$DEPLOY_DIR/.env}"
STACK_FILE="$DEPLOY_DIR/stack.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Arquivo de ambiente não encontrado: $ENV_FILE" >&2
  echo "Copie $DEPLOY_DIR/.env.example para $ENV_FILE e preencha os valores." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

required_vars=(
  STACK_NAME
  IMAGE_REPO
  IMAGE_TAG
  PUBLIC_HOST
  TRAEFIK_NETWORK
  TRAEFIK_ENTRYPOINT
  TRAEFIK_CERTRESOLVER
  WACALLS_API_KEY
  WACALLS_PUBLIC_IP
  WACALLS_UDP_PORT
  WACALLS_MAX_CALLS
  WACALLS_PG_NAMESPACE
  POSTGRES_DB
  POSTGRES_USER
  POSTGRES_PASSWORD
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Variável obrigatória ausente: $var" >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "Docker indisponível neste host." >&2
  exit 1
fi

if ! docker network inspect "$TRAEFIK_NETWORK" >/dev/null 2>&1; then
  echo "Criando rede overlay externa do Traefik: $TRAEFIK_NETWORK"
  docker network create --driver overlay --attachable "$TRAEFIK_NETWORK"
fi

echo "==> Buildando imagem ${IMAGE_REPO}:${IMAGE_TAG}"
docker build -t "${IMAGE_REPO}:${IMAGE_TAG}" "$ROOT_DIR"

echo "==> Publicando imagem ${IMAGE_REPO}:${IMAGE_TAG}"
docker push "${IMAGE_REPO}:${IMAGE_TAG}"

echo "==> Validando stack renderizada"
docker stack config -c "$STACK_FILE" >/dev/null

echo "==> Fazendo deploy da stack ${STACK_NAME}"
docker stack deploy --with-registry-auth --prune -c "$STACK_FILE" "$STACK_NAME"

echo "==> Deploy enviado. Consulte com: docker stack services ${STACK_NAME}"