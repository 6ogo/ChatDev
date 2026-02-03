# ── Stage 1: Build the Vue frontend ──────────────────────────────
FROM node:22-alpine AS frontend-build
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm config set registry https://nexusrm.lfnet.se/repository/npm-group/ && \
    npm config set fetch-timeout 60000 && \
    npm config set fetch-retries 5 && \
    npm config set strict-ssl false && \
    npm config set audit false && \
    npm install --legacy-peer-deps --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

# ── Stage 2: Python backend ─────────────────────────────────────
FROM python:3.12-slim AS backend

# System dependencies for compiled Python packages (cartopy, faiss, pygame, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgeos-dev \
    libproj-dev \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-mixer-dev \
    libsdl2-ttf-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast Python package manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app

# Configure pip/uv to use corporate proxy and disable SSL verification
ENV UV_INDEX_URL=https://nexusrm.lfnet.se/repository/pypi-group/simple \
    UV_EXTRA_INDEX_URL=https://nexusrm.lfnet.se/repository/pypi-proxy/simple \
    UV_NO_VERIFY_SSL=1 \
    PIP_INDEX_URL=https://nexusrm.lfnet.se/repository/pypi-group/simple \
    PIP_EXTRA_INDEX_URL=https://nexusrm.lfnet.se/repository/pypi-proxy/simple \
    PIP_TRUSTED_HOST="nexusrm.lfnet.se"

# Install Python dependencies first (cached layer)
COPY requirements.txt ./
RUN python -m pip install --no-cache-dir -r requirements.txt

# Copy backend source
COPY check/ check/
COPY entity/ entity/
COPY functions/ functions/
COPY runtime/ runtime/
COPY schema_registry/ schema_registry/
COPY server/ server/
COPY tools/ tools/
COPY utils/ utils/
COPY workflow/ workflow/
COPY run.py server_main.py ./

# Copy workflow YAML instance files
COPY yaml_instance/ yaml_instance/

# Copy built frontend into static serving directory
COPY --from=frontend-build /app/frontend/dist /app/frontend/dist

# Create required directories
RUN mkdir -p logs data temp WareHouse

# Expose backend port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the FastAPI server via uv
CMD ["uv", "run", "python", "server_main.py", "--host", "0.0.0.0", "--port", "8000"]
