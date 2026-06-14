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

# Runtime compatibility patch for the plugin's ctypes wrappers.
# The plugin targets an old obspy: it imports the private helper
# `obspy.core.util.libnames._get_lib_name`, which obspy >=1.4 removed, so any
# actual FTAN/tomography run crashed with ImportError even though the plugin
# "loaded" at the CLI. The compiled libs are named plainly (vg_fta.so, ...), so
# we drop the obspy import and build the filename directly. `future` (used by
# the same wrappers for native_str) is pinned in requirements.lock.
RUN set -e; \
    LIBDIR="$(python -c 'import os,msnoise_tomo;print(os.path.join(os.path.dirname(msnoise_tomo.__file__),"lib"))')"; \
    for f in libvg_fta libmkMatSmoothing libmk_MatPaths; do \
        sed -i 's/^from obspy.core.util.libnames import cleanse_pymodule_filename, _get_lib_name/from obspy.core.util.libnames import cleanse_pymodule_filename/' "$LIBDIR/$f.py"; \
        sed -i 's/_get_lib_name(lib, *add_extension_suffix=True)/(lib + ".so")/' "$LIBDIR/$f.py"; \
    done; \
    python -c "import msnoise_tomo.lib.libvg_fta, msnoise_tomo.lib.libmkMatSmoothing, msnoise_tomo.lib.libmk_MatPaths; print('tomo ctypes wrappers import OK')"

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

# Fail the build early if anything is mismatched. This goes beyond importing:
# it runs a real FTAN computation on the plugin's bundled test SAC through the
# compiled vg_fta extension, so a broken tomography path fails the build instead
# of shipping a "loads but can't compute" image.
RUN python -c "import msnoise, msnoise_tomo; print('imports OK')" && \
    python -c "import os, shutil, tempfile, msnoise_tomo; \
from msnoise_tomo.lib.libvg_fta import ftan; \
d=tempfile.mkdtemp(); cwd=os.getcwd(); os.chdir(d); \
sac=os.path.join(os.path.dirname(msnoise_tomo.__file__),'test','data','DK_NRS_DK_NUUG_Sym.SAC'); \
shutil.copy(sac,'t.SAC'); \
ftan('t.SAC',1.0,25.0,0.5,5.0,1.0,200.0,0,100,0.05,0); \
assert os.path.getsize('write_amp.txt')>0, 'FTAN produced no output'; \
os.chdir(cwd); shutil.rmtree(d); print('FTAN smoke test OK -> build OK')"

WORKDIR /project
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5000 8888
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["msnoise", "info"]
