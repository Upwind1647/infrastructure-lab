# Build dependencies and virtualenv using uv in an isolated stage
FROM python:3.14-slim AS builder

# Copy uv CLI (fast Python package manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

# Set environment to optimize for Docker and bytecode
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1

# Copy only dependency metadata for layer caching
COPY pyproject.toml uv.lock ./

# Install Python dependencies into a dedicated virtualenv
RUN uv venv /opt/venv && \
    VIRTUAL_ENV=/opt/venv uv sync --frozen --no-dev --no-install-project

# Final runtime image
FROM python:3.14-slim AS runner

WORKDIR /app

# Ensure Python output is unbuffered and venv is active
ENV PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Create a non-root user for security
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -d /app -s /usr/sbin/nologin appuser

# Copy virtualenv from builder stage, plus the application code
COPY --from=builder /opt/venv /opt/venv
COPY --chown=appuser:appgroup app.py .

USER appuser

EXPOSE 8000

# Container healthcheck on /health endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]

# Start API server with Uvicorn
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
