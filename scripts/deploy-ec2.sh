#!/bin/sh
set -eu

AWS_REGION="us-east-2"
AWS_ACCOUNT_ID="311937350493"
IMAGE_TAG="${1:?Usage: deploy-ec2.sh IMAGE_TAG}"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
NETWORK="ecommerce-net"
UPLOADS_HOST_DIR="/opt/ecommerce/backend-uploads"

BACKEND_ENV_FILE=$(mktemp /tmp/ecommerce-backend-env.XXXXXX)
chmod 600 "$BACKEND_ENV_FILE"

DEPLOY_CHANGED=0
DEPLOY_SUCCESS=0
OLD_BACKEND_IMAGE_ID=""
OLD_FRONTEND_IMAGE_ID=""

finish() {
    status=$?
    trap - EXIT

    if [ "$DEPLOY_SUCCESS" -ne 1 ] && [ "$DEPLOY_CHANGED" -eq 1 ]; then
        echo "Deployment failed. Attempting rollback..."

        docker rm -f backend frontend >/dev/null 2>&1 || true

        if [ -n "$OLD_BACKEND_IMAGE_ID" ] && [ -s "$BACKEND_ENV_FILE" ]; then
            docker run -d \
                --name backend \
                --restart unless-stopped \
                --network "$NETWORK" \
                --env-file "$BACKEND_ENV_FILE" \
                -v "$UPLOADS_HOST_DIR:/app/backend/uploads" \
                -p 5000:5000 \
                "$OLD_BACKEND_IMAGE_ID" || true
        fi

        if [ -n "$OLD_FRONTEND_IMAGE_ID" ]; then
            docker run -d \
                --name frontend \
                --restart unless-stopped \
                --network "$NETWORK" \
                -p 80:80 \
                "$OLD_FRONTEND_IMAGE_ID" || true
        fi
    fi

    rm -f "$BACKEND_ENV_FILE"
    exit "$status"
}
trap finish EXIT

echo "Checking current containers and network..."
docker inspect backend >/dev/null
docker inspect frontend >/dev/null
docker inspect mongodb >/dev/null
docker network inspect "$NETWORK" >/dev/null

OLD_BACKEND_IMAGE_ID=$(docker inspect --format '{{.Image}}' backend)
OLD_FRONTEND_IMAGE_ID=$(docker inspect --format '{{.Image}}' frontend)

docker inspect backend --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -E '^(NODE_ENV|PORT|MONGO_URI|JWT_SECRET)=' > "$BACKEND_ENV_FILE"

for key in NODE_ENV PORT MONGO_URI JWT_SECRET; do
    if ! grep -q "^${key}=" "$BACKEND_ENV_FILE"; then
        echo "Required backend setting is missing: $key" >&2
        exit 1
    fi
done

echo "Preserving existing uploads..."
mkdir -p "$UPLOADS_HOST_DIR"
docker cp backend:/app/backend/uploads/. "$UPLOADS_HOST_DIR/"

echo "Logging in to ECR and pulling new images..."
aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$REGISTRY"

docker pull "$REGISTRY/ecommerce-backend:$IMAGE_TAG"
docker pull "$REGISTRY/ecommerce-frontend:$IMAGE_TAG"

wait_for_url() {
    label="$1"
    url="$2"
    attempt=1

    while [ "$attempt" -le 30 ]; do
        if curl -fsS --max-time 4 "$url" >/dev/null; then
            echo "$label health check passed."
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    echo "$label health check failed: $url" >&2
    return 1
}

echo "Replacing application containers..."
DEPLOY_CHANGED=1
docker rm -f backend frontend >/dev/null

docker run -d \
    --name backend \
    --restart unless-stopped \
    --network "$NETWORK" \
    --env-file "$BACKEND_ENV_FILE" \
    -v "$UPLOADS_HOST_DIR:/app/backend/uploads" \
    -p 5000:5000 \
    "$REGISTRY/ecommerce-backend:$IMAGE_TAG"

docker run -d \
    --name frontend \
    --restart unless-stopped \
    --network "$NETWORK" \
    -p 80:80 \
    "$REGISTRY/ecommerce-frontend:$IMAGE_TAG"

wait_for_url "Backend API" "http://127.0.0.1:5000/api/v1/products"
wait_for_url "Frontend" "http://127.0.0.1/"
wait_for_url "Frontend API proxy" "http://127.0.0.1/api/v1/products"

DEPLOY_SUCCESS=1
echo "Deployment successful: $IMAGE_TAG"
docker ps --filter "name=backend" --filter "name=frontend" \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
