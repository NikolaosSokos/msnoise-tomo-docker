# MSNoise + MSNoise-Tomo, ready to run.
#
# The msnoise-tomo plugin ships C/C++ extension modules built with
# scikit-build-core + CMake, so this image bakes in the compiler toolchain.
# Every dependency is pinned in requirements.lock for byte-for-byte
# reproducibility. msnoise-tomo's master is officially "not stable", so it is
# pinned to a known-good commit.
FROM python:3.10-slim-bookworm

# Pinned commit of ThomasLecocq/msnoise-tomo (override at build time if needed).
ARG TOMO_REF=affcaa4bf33027b01d9290cb1567302045d6c027

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    MPLBACKEND=Agg

# System dependencies:
#  - build-essential, cmake, git, ninja-build: compile the tomo C/C++ extensions
#  - libgl1, libglib2.0-0: runtime libs some matplotlib/obspy paths need
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git ninja-build \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# 1) Pinned scientific + web stack. The web stack is pinned to Flask 2.2.x on
#    purpose: msnoise-tomo does `from flask import Markup`, which Flask >=2.3
#    removed. Without this pin, enabling the plugin crashes the whole CLI.
COPY requirements.lock .
RUN pip install --no-cache-dir -r requirements.lock

# 2) MSNoise-Tomo plugin, compiled from the pinned commit.
#    --no-build-isolation forces the build to use the numpy 1.26 from the lock
#    so the compiled C-extensions match the runtime numpy ABI.
RUN pip install --no-cache-dir --no-build-isolation \
        "git+https://github.com/ThomasLecocq/msnoise-tomo.git@${TOMO_REF}"

# 3) JupyterLab for the optional interactive profile.
RUN pip install --no-cache-dir "jupyterlab>=4,<5"

# Fail the build early if anything is mismatched.
RUN python -c "import msnoise, msnoise_tomo; from msnoise_tomo import lib; print('build OK')"

WORKDIR /project
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5000 8888
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["msnoise", "info"]
