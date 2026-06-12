# MSNoise + MSNoise-Tomo — ready-to-run Docker environment

A reproducible, pre-configured [MSNoise](https://www.msnoise.org/) installation
**with the [msnoise-tomo](https://msnoise.org/plugins/msnoise-tomo/doc/) plugin
already compiled and working** — so you don't have to fight Python versions,
old `obspy` pins, dead plugin wheels, or C/C++ build errors.

Everything runs inside Docker. You only need Docker installed; you do **not**
need Python, conda, a compiler, or anything else on your machine.

---

## Why this exists

Installing msnoise-tomo by hand is fragile:

- The plugin's documented install uses **Python 3.7 + obspy 1.1.1**, which no
  longer build on modern systems.
- Its old **pre-compiled wheels are gone** (they were hosted on Bintray, which
  was shut down).
- The plugin contains **C/C++ code** that must be compiled, so it needs a
  matching compiler toolchain.
- It does `from flask import Markup`, which **modern Flask (≥2.3) removed** — so
  with an up-to-date Flask, enabling the plugin *crashes the whole `msnoise`
  command*.

This image fixes all of that by pinning a coherent, tested set of versions
(see [`requirements.lock`](requirements.lock)) and compiling the plugin from a
known-good commit during the build.

---

## Prerequisites

| OS | What to install |
|----|-----------------|
| **Windows** | [Docker Desktop](https://www.docker.com/products/docker-desktop/) (uses the WSL2 backend — accept the default). |
| **Linux** | [Docker Engine](https://docs.docker.com/engine/install/) + the Docker Compose plugin. |

Verify it works:

```bash
docker --version
docker compose version
```

---

## Quick start

**1. Get the project**

```bash
git clone https://github.com/NikolaosSokos/msnoise-tomo-docker.git
cd msnoise-tomo-docker
```

**2. Create your settings file**

Linux / macOS:
```bash
cp .env.example .env
```
Windows (PowerShell):
```powershell
Copy-Item .env.example .env
```

**3. Build the image** (first time only — takes a few minutes)

```bash
docker compose build
```

That's it. The image now contains MSNoise + a working msnoise-tomo plugin.

---

## Running it

There are three ways to use it. Pick whichever you need — they all share the
same `./project` (your MSNoise project + database) and `./data` (your seismic
data) folders.

### A) Command line (the normal MSNoise workflow)

Run any `msnoise` command by putting it after `docker compose run --rm msnoise`:

```bash
docker compose run --rm msnoise msnoise info
docker compose run --rm msnoise msnoise p tomo --help     # the tomo plugin
```

The **first** command you run automatically initialises the project database
and enables the tomo plugin. After that your project lives in `./project/` and
persists between runs.

To get an interactive shell inside the container:

```bash
docker compose run --rm msnoise bash
```

### B) Web admin GUI

```bash
docker compose --profile web up
```

Then open **http://localhost:5000** in your browser. Press `Ctrl+C` to stop.

### C) JupyterLab (interactive analysis & plotting)

```bash
docker compose --profile jupyter up
```

Then open **http://localhost:8888** and enter the token `msnoise` (configurable
in `.env`). Your project is mounted at `/project`.

---

## Using your own seismic data

Put your data (e.g. miniSEED / SDS archive) in the **`data/`** folder. It is
mounted **read-only** inside the container at `/data`. For example, to scan it:

```bash
docker compose run --rm msnoise msnoise scan_archive --init
```

(Configure the data folder path as `/data` in the MSNoise configuration.)

---

## Optional: use MariaDB instead of SQLite

SQLite (the default) is perfect for getting started and for most projects. For
very large datasets or heavy parallel processing, MSNoise recommends MySQL /
MariaDB. To switch:

1. In `.env`, set:
   ```ini
   DB_TECH=mysql
   ```
2. Start with the `mysql` profile added to whatever you're launching, e.g.:
   ```bash
   docker compose --profile mysql --profile web up
   ```
   or for the CLI:
   ```bash
   docker compose --profile mysql run --rm msnoise msnoise info
   ```

The database is created automatically and stored in a Docker volume
(`mariadb_data`). Credentials are set in `.env`.

> **Note:** the database backend is chosen the first time the project is
> initialised. To switch backends on an existing project, clear `./project/`
> (this deletes the SQLite project) and re-initialise.

---

## Updating / rebuilding

```bash
git pull
docker compose build --no-cache
```

Your `./project` and `./data` are untouched by a rebuild.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `docker: command not found` / daemon not running | Start Docker Desktop (Windows) or `sudo systemctl start docker` (Linux). |
| Port 5000 or 8888 already in use | Change `WEB_PORT` / `JUPYTER_PORT` in `.env`. |
| Want a clean slate | Delete the contents of `./project/` (SQLite) and, for MariaDB, `docker compose down -v`. |
| Build seems stuck | The first build compiles the plugin and downloads obspy — give it a few minutes. |

---

## What's pinned (and why it works)

- **Python 3.10**, **numpy 1.26**, **obspy 1.5**, **MSNoise 1.6.5**
- **Flask 2.2.5 / Flask-Admin 1.6.1** — the key fix that keeps `flask.Markup`
  available so the tomo plugin loads.
- **msnoise-tomo** compiled from commit
  [`affcaa4`](https://github.com/ThomasLecocq/msnoise-tomo/commit/affcaa4bf33027b01d9290cb1567302045d6c027).

Full list: [`requirements.lock`](requirements.lock).

---

## Credits

- [MSNoise](https://www.msnoise.org/) and
  [msnoise-tomo](https://github.com/ThomasLecocq/msnoise-tomo) by Thomas Lecocq
  (Royal Observatory of Belgium) and the MSNoise dev team.
- This packaging just wraps their work in a reproducible container.
