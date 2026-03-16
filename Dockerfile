FROM python:3.12-slim AS builder


# Bring  uv CLI into the image
COPY --from=ghcr.io/astral-sh/uv:0.4.24 /uv /uvx /bin/

WORKDIR /app

# Optimizations for Docker and bytecode, and exclude dev dependencies
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    PYTHONUNBUFFERED=1 \
    UV_PYTHON_DOWNLOADS=never

COPY pyproject.toml uv.lock ./

# Install dependencies
RUN uv sync --frozen --no-install-project

FROM python:3.12-slim AS runner

# Security Patching
RUN apt-get update && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Use the  environment under /app/.venv
ENV PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

# Non-root user
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -d /app -s /usr/sbin/nologin appuser

# Copy the virtual environment and the application
COPY --from=builder /app/.venv /app/.venv
COPY --chown=appuser:appgroup app.py .

USER appuser

EXPOSE 8000

# Container healthcheck using the /health endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]

# Start the FastAPI application via Uvicorn
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
