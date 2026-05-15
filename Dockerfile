# Base image provided by Cloudflare — includes the sandbox control-plane
# server that listens on port 3000 and handles all SDK API calls.
#
# Version sync rule (verbatim, developers.cloudflare.com/sandbox/configuration/dockerfile/):
# "Always match the Docker image version to your npm package version.
# The SDK automatically checks version compatibility on startup.
# Mismatched versions can cause features to break or behave unexpectedly."
#
# This tag MUST match the @cloudflare/sandbox pin in package.json (0.9.2).
FROM docker.io/cloudflare/sandbox:0.9.2

# === Layer 1: Mirror upstream bridge tooling =================================
# Verbatim from cloudflare/sandbox-sdk/bridge/worker/Dockerfile (2026-04-30).
# tar        - persist_workspace / hydrate_workspace
# git        - version control (log, blame, diff, status, commit, restore, revert)
# curl/wget  - HTTP fetching (used by pdf-factory's fetch_icons.py)
# ripgrep    - preferred by agent prompts for text/file search
# jq         - JSON processing
# procps     - process management (ps, pkill, kill)
# sed/gawk   - text processing utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    tar \
    git \
    curl \
    wget \
    ripgrep \
    jq \
    procps \
    sed \
    gawk \
    && rm -rf /var/lib/apt/lists/*

# fusermount requires /etc/mtab to find active mounts. The base image does
# not include it, causing `fusermount -u` to fail silently during bucket
# unmount. Verbatim fix from upstream.
RUN ln -sf /proc/mounts /etc/mtab

# Install uv (Python package manager) and use it to install Python 3.13.
# Verbatim from upstream — uv is faster than pip and handles wheels reliably
# for the C-extension packages our skills need (lxml, pillow, reportlab).
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python
RUN uv python install 3.13

# Create a venv we can install into freely. uv's managed Python has an
# EXTERNALLY-MANAGED marker (PEP 668) that blocks `--system` pip installs;
# the venv pattern is the canonical workaround and matches PEP 668's
# recommendation. Putting the venv's bin on PATH so `python3`/`python`
# transparently use it inside sandbox.exec() — skill scripts that
# `#!/usr/bin/env python3` resolve to our pre-installed packages.
RUN uv venv /opt/skill-runtime --python 3.13
ENV VIRTUAL_ENV=/opt/skill-runtime
ENV PATH=/opt/skill-runtime/bin:$PATH

# Workspace root used by the sandbox service.
RUN mkdir -p /workspace

# === Layer 2: Gizmo skill stack =============================================
# Pre-install all Python packages our in-scope catalog (docs-factory,
# epub-generator, skills-factory) declares. Baking them in means first
# /exec is fast (no pip install per discussion).
#
# Catalog mapping:
# - pdf-factory      → reportlab pypdf markdown lxml pillow html5lib
#                      cssselect2 pyhanko python-bidi arabic-reshaper
#                      (+ rlpycairo svglib xhtml2pdf via --no-deps)
# - chart-designer   → matplotlib
# - epub-creator     → ebooklib markdown pillow beautifulsoup4 lxml PyYAML
# - skills-factory/* → PyYAML (the rest is stdlib only)
#
# pdf-factory's install_deps.py uses --no-deps for svglib + rlpycairo +
# xhtml2pdf to avoid building the pycairo C extension (which requires the
# system cairo library). We mirror that decision here.
RUN uv pip install --no-cache-dir \
    reportlab \
    pypdf \
    markdown \
    lxml \
    pillow \
    html5lib \
    cssselect2 \
    pyhanko \
    python-bidi \
    arabic-reshaper \
    matplotlib \
    ebooklib \
    beautifulsoup4 \
    PyYAML

RUN uv pip install --no-cache-dir --no-deps \
    rlpycairo \
    svglib \
    xhtml2pdf

# === Layer 3: Non-root user =================================================
# Verbatim from upstream — defense-in-depth. Commands executed via
# sandbox.exec() run as this user, limiting access to sensitive system
# files.
RUN useradd -m -s /bin/bash -d /home/sandbox sandbox \
    && chown sandbox:sandbox /workspace \
    && chmod 700 /root

USER sandbox
WORKDIR /workspace
