# 1. Prerequisites

- **Windows 11** with **WSL2** installed (Ubuntu recommended).
- **Docker Desktop** (WSL2 integration enabled).
- **VS Code** with Remote - WSL and Dev Containers extensions.
- Python toolchain:
  - `pyenv` for version mgmt.
  - `uv` as the package manager.
  - `pipx` for global CLIs.

Verify with:
```bash
wsl --status
docker version
code --version
```

> Important: All repos and containers live **inside WSL2** for consistency.
