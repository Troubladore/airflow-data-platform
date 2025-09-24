#!/bin/bash
# Docker state detection - focused, testable component

set -euo pipefail

# Returns:
# 0 = Docker fully operational
# 1 = Docker CLI missing
# 2 = Docker daemon not accessible
# 3 = Docker proxy needs configuration

detect_docker_cli() {
    if command -v docker &>/dev/null; then
        echo "DOCKER_CLI=available"
        return 0
    else
        echo "DOCKER_CLI=missing"
        return 1
    fi
}

detect_docker_daemon() {
    if docker info &>/dev/null; then
        echo "DOCKER_DAEMON=running"
        return 0
    else
        echo "DOCKER_DAEMON=not_accessible"

        # Diagnose the specific issue
        if docker version &>/dev/null; then
            echo "DOCKER_ISSUE=daemon_not_running"
        else
            echo "DOCKER_ISSUE=wsl2_integration_missing"
        fi
        return 2
    fi
}

detect_docker_proxy() {
    local proxy_config=$(docker info --format '{{.HTTPProxy}}' 2>/dev/null || echo "")
    local no_proxy_config=$(docker info --format '{{.NoProxy}}' 2>/dev/null || echo "")

    if [ -n "$proxy_config" ]; then
        echo "DOCKER_PROXY=$proxy_config"
        if [[ "$no_proxy_config" == *"*.localhost"* ]]; then
            echo "PROXY_BYPASS=configured"
            return 0
        else
            echo "PROXY_BYPASS=missing"
            return 3
        fi
    else
        echo "DOCKER_PROXY=none"
        echo "PROXY_BYPASS=not_needed"
        return 0
    fi
}

main() {
    local exit_code=0

    detect_docker_cli || exit_code=$?
    [ $exit_code -ne 1 ] && detect_docker_daemon || exit_code=$?
    [ $exit_code -eq 0 ] && detect_docker_proxy || exit_code=$?

    echo "DOCKER_STATUS=$exit_code"
    return $exit_code
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
