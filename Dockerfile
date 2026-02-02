# ── Stage 1: Build the Vue frontend ──────────────────────────────
FROM node:22-alpine AS frontend-build

WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm install
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

# Install Python dependencies first (cached layer)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# Copy backend source
COPY backend/ backend/
COPY runtime/ runtime/
COPY server/ server/
COPY configuration/ configuration/
COPY run.py server_main.py ./

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
