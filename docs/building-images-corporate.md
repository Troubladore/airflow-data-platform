# Building Docker Images in Corporate Environments

Quick reference for building images when public registries are blocked.

## Key Principles

1. **Base images:** Use `ARG IMAGE_*` variables from .env
2. **Package installs (apk/apt):** Usually work via package mirrors (or use base from Artifactory)
3. **Python packages (pip/uv):** Need credentials + index URL
4. **Binary downloads (curl):** May need Artifactory mirrors

## Python Package Installation Pattern

### The Problem
Corporate environments block public PyPI. Your machine works because:
- `~/.config/uv/uv.toml` or `~/.pip/pip.conf` → index URL
- `~/.netrc` or env vars → credentials

**But Docker build has NONE of these!**

### The Solution (3 steps)

**1. Auto-detect index from host:**
```makefile
# Makefile
AUTO_INDEX=$(python3 -c "import tomllib; ..." 2>/dev/null)
docker build --build-arg PIP_INDEX_URL=$$AUTO_INDEX ...
```

**2. Mount .netrc as BuildKit secret:**
```bash
docker build --secret id=netrc,src=${HOME}/.netrc ...
```

**3. Use in single RUN with .netrc mounted:**
```dockerfile
ARG PIP_INDEX_URL
RUN --mount=type=secret,id=netrc,target=/root/.netrc \
    pip config set global.index-url "$PIP_INDEX_URL" && \
    pip install uv && \
    uv pip install your-package
```

**Why single RUN:** .netrc needed for ALL pip operations (including installing UV itself)

## Example: kerberos-sidecar/Dockerfile.test-image

See `platform-bootstrap/kerberos-sidecar/Dockerfile.test-image` for complete working example.

**Build:**
```bash
cd platform-bootstrap/kerberos-sidecar
make build-test-image  # Auto-detects everything
```

## Corporate Checklist

Before building images:
- [ ] Configure `~/.config/uv/uv.toml` or `~/.pip/pip.conf` (index URL)
- [ ] Configure `~/.netrc` (credentials)
- [ ] Set `IMAGE_*` variables in .env (base images)
- [ ] Run `docker login` for Artifactory (Docker images)

Then all builds "just work"!

## Troubleshooting

**"User for {artifactory}: " prompt:**
- Missing .netrc credentials
- Check: `cat ~/.netrc` has `machine artifactory.company.com`

**"SSL: UNEXPECTED_EOF":**
- Corporate firewall blocking
- Need Artifactory mirror for that package source

**"pip install uv" fails:**
- Corporate Python image pre-configured for corporate PyPI
- Need .netrc mounted in SAME RUN as `pip install uv`
