# MSNoise + MSNoise-Tomo, ready to run.
#
# Multi-stage build: the heavy compiler toolchain (build-essential, cmake, ...)
# lives only in the builder stage and is NOT shipped in the final image, which
# roughly halves its size. Every dependency is pinned in requirements.lock for
# byte-for-byte reproducibility. msnoise-tomo's master is officially "not
# stable", so it is pinned to a known-good commit.

# ---------- Stage 1: build everything into a self-contained venv ----------
FROM python:3.10-slim-bookworm AS builder

ARG TOMO_REF=affcaa4bf33027b01d9290cb1567302045d6c027
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH=/opt/venv/bin:$PATH

# Compiler toolchain needed only to compile the tomo C/C++ extensions.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git ninja-build \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv

# Pinned scientific + web stack. The web stack is pinned to Flask 2.2.x on
# purpose: msnoise-tomo does `from flask import Markup`, which Flask >=2.3
# removed; without this pin, enabling the plugin crashes the whole CLI.
COPY requirements.lock .
RUN pip install --no-cache-dir -r requirements.lock

# MSNoise-Tomo plugin, compiled from the pinned commit. --no-build-isolation
# forces the build to use numpy 1.26 from the lock so the compiled C-extensions
# match the runtime numpy ABI.
RUN pip install --no-cache-dir --no-build-isolation \
        "git+https://github.com/ThomasLecocq/msnoise-tomo.git@${TOMO_REF}"

# JupyterLab for the optional interactive profile.
RUN pip install --no-cache-dir "jupyterlab>=4,<5"

# ---------- Stage 2: slim runtime image ----------
FROM python:3.10-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    MPLBACKEND=Agg \
    PATH=/opt/venv/bin:$PATH

# Only the runtime shared libraries the compiled extensions / plotting need.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libstdc++6 libgomp1 libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Bring over the fully-built virtual environment from the builder stage.
COPY --from=builder /opt/venv /opt/venv

# Fail the build early if anything is mismatched.
RUN python -c "import msnoise, msnoise_tomo; from msnoise_tomo import lib; print('build OK')"

WORKDIR /project
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5000 8888
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["msnoise", "info"]
