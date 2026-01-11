DTRACK_DIR          := "./dependency-track"
DTRACK_COMPOSE_URL  := "https://dependencytrack.org/docker-compose.yml"
DTRACK_COMPOSE_FILE := DTRACK_DIR + "/docker-compose.yml"


default: help


help:
    @cat help.txt


dtrack-start: _dtrack-download _dtrack-patch
    @echo "--- Starting Dependency-Track ---"
    @docker compose -f {{DTRACK_COMPOSE_FILE}} up -d
    @echo "----------------------------------------------------------------"
    @if [ -n "$CODESPACE_NAME" ]; then \
        echo "==> Environment: GitHub Codespaces"; \
        echo "==> Frontend URL: https://$CODESPACE_NAME-8080.$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"; \
        echo "==> API URL:      https://$CODESPACE_NAME-8081.$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"; \
    else \
        echo "==> Environment: Localhost"; \
        echo "==> Frontend URL: http://localhost:8080"; \
        echo "==> API URL:      http://localhost:8081"; \
    fi
    @echo "----------------------------------------------------------------"


dtrack-stop:
    @echo "--- Stopping Dependency-Track ---"
    @if [ -f {{DTRACK_COMPOSE_FILE}} ]; then \
        docker compose -f {{DTRACK_COMPOSE_FILE}} down; \
    fi
    @echo "--- Dependency-Track stopped ---"


dtrack-restart: dtrack-stop dtrack-start


_dtrack-download:
    @if [ ! -f {{DTRACK_COMPOSE_FILE}} ]; then \
        echo "=> Downloading docker-compose.yml for Dependency-Track..."; \
        mkdir -p {{DTRACK_DIR}}; \
        curl -fsSL {{DTRACK_COMPOSE_URL}} -o {{DTRACK_COMPOSE_FILE}}; \
    fi

_dtrack-patch:
    #!/usr/bin/env bash
    set -e
    COMPOSE_FILE="{{DTRACK_COMPOSE_FILE}}"

    if [ -z "$DTRACK_API_URL" ] && [ -n "$CODESPACE_NAME" ]; then
        DETECTED_URL="https://$CODESPACE_NAME-8081.$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"
        echo "=> Auto-detected Codespaces API URL: $DETECTED_URL"
        yq -i ".services.frontend.environment.API_BASE_URL = \"$DETECTED_URL\"" "$COMPOSE_FILE"
    elif [ -n "$DTRACK_API_URL" ]; then
        echo "=> Using provided DTRACK_API_URL: $DTRACK_API_URL"
        yq -i ".services.frontend.environment.API_BASE_URL = \"$DTRACK_API_URL\"" "$COMPOSE_FILE"
    else
        echo "=> No specific API URL detected. Defaulting to localhost config."
    fi

    echo "=> Ensuring CORS is enabled..."
    yq -i '.services.apiserver.environment.ALPINE_CORS_ENABLED = "true"' "$COMPOSE_FILE"

    CURRENT_ORIGIN=$(yq '.services.apiserver.environment.ALPINE_CORS_ALLOW_ORIGIN' "$COMPOSE_FILE")
    if [ "$CURRENT_ORIGIN" = "null" ] || [ -z "$CURRENT_ORIGIN" ]; then
        echo "=> Setting default CORS Origin to *"
        yq -i '.services.apiserver.environment.ALPINE_CORS_ALLOW_ORIGIN = "*"' "$COMPOSE_FILE"
    fi

dtrack-add-trivy:
    #!/usr/bin/env bash
    set -e
    COMPOSE_FILE="{{DTRACK_COMPOSE_FILE}}"
    TRIVY_TOKEN="MySecretTrivyToken"

    echo "=> Checking if Trivy service exists..."

    if [ "$(yq '.services.trivy' "$COMPOSE_FILE")" = "null" ]; then
        echo "=> Trivy service not found. Injecting configuration..."
        
        export T_TOKEN="$TRIVY_TOKEN"
        
        yq -i '.services.trivy.image = "aquasec/trivy:latest"' "$COMPOSE_FILE"
        yq -i '.services.trivy.command = "server --listen :8080 --token " + strenv(T_TOKEN)' "$COMPOSE_FILE"
        yq -i '.services.trivy.ports = ["8085:8080"]' "$COMPOSE_FILE"
        yq -i '.services.trivy.volumes = ["trivy-cache:/root/.cache/trivy"]' "$COMPOSE_FILE"
        yq -i '.services.trivy.restart = "unless-stopped"' "$COMPOSE_FILE"
        
        yq -i '.volumes.trivy-cache = {}' "$COMPOSE_FILE"
        
        echo "=> Trivy service injected successfully."
        echo "=> NOTE: Use Token '$TRIVY_TOKEN' and URL 'http://trivy:8080' in Dependency-Track settings."
    else
        echo "=> Trivy service already exists. Skipping injection."
    fi