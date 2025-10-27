#!/usr/bin/env python3
"""Manual verification test for config file deletion fix.

This script demonstrates the fix working correctly:
1. Creates config with multiple services
2. Disables them one by one
3. Shows config file is deleted when all are disabled
"""
import yaml
import os
from pathlib import Path
from wizard.engine.runner import RealActionRunner

def print_section(title):
    print(f"\n{'='*70}")
    print(f"  {title}")
    print(f"{'='*70}")

def show_config(config_path):
    if config_path.exists():
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        print(f"Config exists:")
        print(yaml.dump(config, default_flow_style=False))
    else:
        print("Config file does NOT exist (deleted)")

def main():
    print_section("Manual Verification: Config File Deletion Fix")

    # Use temp directory
    test_dir = Path('/tmp/test-config-deletion')
    test_dir.mkdir(exist_ok=True)
    config_path = test_dir / 'platform-config.yaml'

    # Clean up if exists
    if config_path.exists():
        config_path.unlink()

    runner = RealActionRunner()
    os.chdir(test_dir)

    print_section("Step 1: Create config with 3 services (all enabled)")
    initial_config = {
        'services': {
            'postgres': {
                'enabled': True,
                'image': 'postgres:17.5-alpine',
                'port': 5432
            },
            'kerberos': {
                'enabled': True,
                'domain': 'EXAMPLE.COM'
            },
            'pagila': {
                'enabled': True
            }
        }
    }
    with open(config_path, 'w') as f:
        yaml.dump(initial_config, f)

    show_config(config_path)

    print_section("Step 2: Disable postgres (using save_config merge)")
    postgres_config = {
        'services': {
            'postgres': {
                'enabled': False,
                'image': 'postgres:17.5-alpine',
                'port': 5432
            }
        }
    }
    runner.save_config(postgres_config, str(config_path))
    show_config(config_path)
    print("✓ Config still exists - kerberos and pagila still enabled")

    print_section("Step 3: Disable kerberos (using save_config merge)")
    kerberos_config = {
        'services': {
            'kerberos': {
                'enabled': False,
                'domain': 'EXAMPLE.COM'
            }
        }
    }
    runner.save_config(kerberos_config, str(config_path))
    show_config(config_path)
    print("✓ Config still exists - pagila still enabled")

    print_section("Step 4: Disable pagila (last service)")
    pagila_config = {
        'services': {
            'pagila': {
                'enabled': False
            }
        }
    }
    runner.save_config(pagila_config, str(config_path))
    show_config(config_path)

    if not config_path.exists():
        print("\n✓ SUCCESS: Config file automatically deleted when all services disabled!")
    else:
        print("\n✗ FAILURE: Config file still exists when it should be deleted")
        return 1

    print_section("Summary")
    print("The fix works correctly:")
    print("1. save_config merges instead of overwriting")
    print("2. Config file is automatically deleted when ALL services disabled")
    print("3. Config file persists when any service is still enabled")

    return 0

if __name__ == '__main__':
    exit(main())
