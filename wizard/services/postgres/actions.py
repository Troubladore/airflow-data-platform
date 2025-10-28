"""PostgreSQL actions - GREEN phase implementation.

Key Design Decision: The 'prebuilt' Flag
=========================================
The prebuilt flag controls whether the platform LAYERS CUSTOMIZATIONS on the image,
NOT whether we pull it from the registry.

- prebuilt=false (default): Platform may add SSL certificates, Kerberos config,
  corporate CA certs, or other customizations at runtime or build time
- prebuilt=true: Use the image AS-IS without any platform modifications
  (image already has everything needed)

Both modes may need to pull the image from a Docker registry.
"""

from typing import Dict, Any


def save_config(ctx: Dict[str, Any], runner) -> None:
    """Save PostgreSQL configuration to platform-config.yaml.

    Builds configuration dictionary from context and calls runner.save_config.

    Args:
        ctx: Context dictionary with service configuration
        runner: ActionRunner instance for side effects
    """
    # Build config dictionary
    # Map require_password boolean to auth_method
    require_password = ctx.get('services.postgres.require_password', True)
    auth_method = 'md5' if require_password else 'trust'
    password = ctx.get('services.postgres.password', 'changeme') if require_password else None

    # Store derived values back into state for later access
    ctx['services.postgres.auth_method'] = auth_method
    if password is not None:
        ctx['services.postgres.password'] = password

    config = {
        'services': {
            'postgres': {
                'enabled': True,
                'image': ctx.get('services.postgres.image', 'postgres:17.5-alpine'),
                'prebuilt': ctx.get('services.postgres.prebuilt', False),
                'auth_method': auth_method,
                'password': password
            }
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')


def pull_image(ctx: Dict[str, Any], runner) -> None:
    """Pull PostgreSQL Docker image.

    The prebuilt flag controls whether we layer customizations on the image,
    NOT whether we pull it. Both modes may need to pull from registry.

    Args:
        ctx: Context dictionary with image URL and prebuilt flag
        runner: ActionRunner instance for side effects
    """
    image = ctx.get('services.postgres.image', 'postgres:17.5-alpine')
    prebuilt = ctx.get('services.postgres.prebuilt', False)

    if prebuilt:
        runner.display(f"\nPulling prebuilt image (will use as-is): {image}")
    else:
        runner.display(f"\nPulling Docker image: {image}")

    # Always pull the image - both modes may need it from registry
    result = runner.run_shell(['docker', 'pull', image])

    if result.get('returncode') == 0:
        if prebuilt:
            runner.display(f"✓ Prebuilt image ready (no customizations): {image}")
        else:
            runner.display(f"✓ Image pulled: {image}")
    else:
        runner.display(f"✗ Failed to pull image: {image}")


def start_service(ctx: Dict[str, Any], runner) -> None:
    """Start PostgreSQL service.

    Calls make start command.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    runner.display("Starting PostgreSQL service...")

    # Build command
    command = ['make', '-C', 'platform-infrastructure', 'start']

    # Execute command
    result = runner.run_shell(command)

    if result.get('returncode') == 0:
        runner.display("✓ PostgreSQL started successfully")
    else:
        runner.display("✗ PostgreSQL failed to start")
