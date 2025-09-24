# Simple Local Registry Solution (No Traefik!)

## The Problem
Need a consistent registry name that works locally and in containers.

## The SIMPLE Solution: Just Use `/etc/hosts`

### Option 1: Direct hosts file entry (Simplest)
```bash
# Add to /etc/hosts (or WSL2's /etc/hosts)
127.0.0.1 registry.local

# That's it! Now you can use:
docker pull registry.local:5000/my-image
```

### Option 2: Use Docker's built-in registry name
```yaml
# docker-compose.yml
services:
  registry:
    image: registry:2
    container_name: registry.local  # This becomes the hostname!
    ports:
      - "5000:5000"
    volumes:
      - registry_data:/var/lib/registry
```

Now from OTHER containers in the same network:
```dockerfile
FROM registry.local:5000/base-image:latest
```

### Option 3: Use localhost with port (Simplest of all)
```bash
# Just embrace the port!
docker tag my-image localhost:5000/my-image
docker push localhost:5000/my-image

# Works from anywhere, no DNS needed
```

## For Astronomer Integration

In your `.astro/config.yaml`:
```yaml
# Tell Astronomer to use local registry
local:
  registry:
    url: localhost:5000  # Or registry.local:5000 if using hosts file
```

## The Real Win: Docker Compose Networks

```yaml
# platform-bootstrap/registry-simple.yml
services:
  registry:
    image: registry:2
    container_name: platform-registry
    hostname: registry  # This is the key!
    networks:
      - platform-net
    ports:
      - "5000:5000"

networks:
  platform-net:
    name: platform_network
    external: true  # Share with Astronomer
```

Now ANY container on `platform_network` can use `registry:5000` directly!

## Production Parity Without Complexity

**Local**: `registry:5000` (Docker network DNS)
**Dev/QA**: `registry.dev.company.com`
**Prod**: `registry.prod.company.com`

Use environment variables:
```bash
# .env
REGISTRY_URL=${REGISTRY_URL:-registry:5000}  # Default to local
```

## What We're NOT Doing
- ❌ No Traefik
- ❌ No certificates for registry
- ❌ No complex DNS
- ❌ No nginx proxy

## What We ARE Doing
- ✅ Simple registry container
- ✅ Direct port access (5000)
- ✅ Docker network DNS (free!)
- ✅ Optional hosts file entry

## The Makefile Target
```makefile
registry-start:
	@docker run -d \
		--name platform-registry \
		--hostname registry \
		--network platform_network \
		-p 5000:5000 \
		-v registry_data:/var/lib/registry \
		registry:2
	@echo "Registry available at:"
	@echo "  - localhost:5000 (from host)"
	@echo "  - registry:5000 (from containers in platform_network)"
```

## Testing It
```bash
# From host
docker pull alpine
docker tag alpine localhost:5000/alpine
docker push localhost:5000/alpine

# From container on same network
docker run --rm --network platform_network alpine \
  wget -qO- http://registry:5000/v2/_catalog
```

---

**Bottom line**: Docker already provides DNS for container names within networks. No Traefik needed!
