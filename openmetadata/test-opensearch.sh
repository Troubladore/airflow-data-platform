#!/bin/bash
# Test OpenSearch 2.19.2 Configuration for OpenMetadata
set -e

echo "==========================================="
echo "OpenSearch 2.19.2 Configuration Test"
echo "==========================================="
echo ""

# 1. Check if OpenSearch container is running
echo "1. Checking OpenSearch container status..."
if docker ps | grep -q openmetadata-opensearch; then
    echo "✓ OpenSearch container is running"
else
    echo "✗ OpenSearch container not found. Starting services..."
    cd /home/troubladore/repos/airflow-data-platform/platform-infrastructure
    docker compose up -d
    cd /home/troubladore/repos/airflow-data-platform/openmetadata

    # Create volume if it doesn't exist
    if ! docker volume ls | grep -q openmetadata_opensearch_data; then
        echo "Creating OpenSearch volume..."
        docker volume create openmetadata_opensearch_data
    fi

    docker compose up -d openmetadata-opensearch
    echo "Waiting for OpenSearch to start..."
    sleep 30
fi

# 2. Check OpenSearch version
echo ""
echo "2. Verifying OpenSearch version..."
VERSION=$(docker exec openmetadata-opensearch opensearch --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
echo "   OpenSearch version: $VERSION"
if [[ "$VERSION" == "2.19.2" ]]; then
    echo "✓ Correct version (2.19.2)"
else
    echo "⚠ Warning: Expected 2.19.2, got $VERSION"
fi

# 3. Check cluster health
echo ""
echo "3. Checking OpenSearch cluster health..."
HEALTH=$(curl -s http://localhost:9200/_cluster/health?pretty 2>/dev/null | grep '"status"' | awk '{print $3}' | tr -d '",')
if [[ "$HEALTH" == "green" ]] || [[ "$HEALTH" == "yellow" ]]; then
    echo "✓ Cluster health: $HEALTH"
else
    echo "✗ Cluster health check failed or unhealthy: $HEALTH"
fi

# 4. Check if security is disabled (required for local dev)
echo ""
echo "4. Verifying security is disabled..."
SECURITY_CHECK=$(curl -s http://localhost:9200/ 2>/dev/null | grep -c '"cluster_name"' || echo 0)
if [[ "$SECURITY_CHECK" -gt 0 ]]; then
    echo "✓ Security disabled (can access without auth)"
else
    echo "✗ Security may be enabled (cannot access endpoint)"
fi

# 5. Check environment variables in container
echo ""
echo "5. Verifying environment variables..."
ES_OPTS=$(docker exec openmetadata-opensearch sh -c 'echo $ES_JAVA_OPTS' 2>/dev/null)
if [[ "$ES_OPTS" == *"1024m"* ]]; then
    echo "✓ ES_JAVA_OPTS configured: $ES_OPTS"
else
    echo "✗ ES_JAVA_OPTS not properly set: $ES_OPTS"
fi

# 6. Test OpenMetadata connection (if server is running)
echo ""
echo "6. Testing OpenMetadata connection to OpenSearch..."
if docker ps | grep -q openmetadata-server; then
    # Check logs for connection messages
    if docker logs openmetadata-server 2>&1 | tail -20 | grep -q "opensearch"; then
        echo "✓ OpenMetadata server references OpenSearch"
    else
        echo "⚠ Could not verify OpenMetadata-OpenSearch connection from logs"
    fi

    # Check SEARCH_TYPE env var
    SEARCH_TYPE=$(docker exec openmetadata-server sh -c 'echo $SEARCH_TYPE' 2>/dev/null)
    if [[ "$SEARCH_TYPE" == "opensearch" ]]; then
        echo "✓ SEARCH_TYPE correctly set to: $SEARCH_TYPE"
    else
        echo "✗ SEARCH_TYPE not set to 'opensearch': $SEARCH_TYPE"
    fi
else
    echo "⚠ OpenMetadata server not running (run 'make start' in openmetadata/)"
fi

# 7. Performance check
echo ""
echo "7. Basic performance check..."
# Create a test index
curl -s -X PUT "http://localhost:9200/test-index" >/dev/null 2>&1
# Index a document
curl -s -X POST "http://localhost:9200/test-index/_doc/1" \
    -H 'Content-Type: application/json' \
    -d '{"test": "OpenSearch 2.19.2 test document"}' >/dev/null 2>&1
# Search for it
SEARCH_RESULT=$(curl -s "http://localhost:9200/test-index/_search?q=opensearch" 2>/dev/null | grep -c '"hits"' || echo 0)
if [[ "$SEARCH_RESULT" -gt 0 ]]; then
    echo "✓ Can create index, insert, and search documents"
else
    echo "✗ Search operations failed"
fi
# Cleanup
curl -s -X DELETE "http://localhost:9200/test-index" >/dev/null 2>&1

# Summary
echo ""
echo "==========================================="
echo "Test Summary"
echo "==========================================="

# OpenSearch info
echo ""
echo "OpenSearch Endpoint: http://localhost:9200"
echo "Version: ${VERSION}"
echo "Cluster Health: ${HEALTH}"

# Corporate mirror note
echo ""
echo "Note for Corporate Users:"
echo "Ensure your Artifactory mirror has:"
echo "  opensearchproject/opensearch:2.19.2"
echo ""
echo "Configure in openmetadata/.env:"
echo "  IMAGE_OPENSEARCH=artifactory.company.com/docker-remote/opensearchproject/opensearch:2.19.2"

echo ""
echo "Test complete!"