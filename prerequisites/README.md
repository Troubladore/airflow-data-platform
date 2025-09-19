# Prerequisites Setup

This directory contains all the foundational components needed before setting up the Astronomer Airflow environment.

## Components

### 1. Windows WSL2 Setup
Complete setup instructions for Windows developers using WSL2.

### 2. Traefik + Registry
- **Traefik**: Reverse proxy for routing to multiple services
- **Registry**: Local Docker registry for storing custom images
- Configured with TLS for secure communication

### 3. TLS Certificates
- Development certificates for `*.localhost` domains
- Options for self-signed or mkcert-based certificates

## Quick Setup

Run the main setup script from the project root:
```bash
../scripts/setup.sh
```

Or set up components individually:

### Traefik and Registry
```bash
cd traefik-registry
docker compose up -d
```

Access points:
- Traefik Dashboard: https://traefik.localhost
- Registry: https://registry.localhost
- Test Service: https://whoami.localhost

### Verify Registry
```bash
docker pull busybox
docker tag busybox registry.localhost/test/busybox:latest
docker push registry.localhost/test/busybox:latest
```

## Network Architecture

All services communicate through the `edge` Docker network, enabling:
- Service discovery
- TLS termination at Traefik
- Isolated communication between containers