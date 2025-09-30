#!/bin/bash

NAMESPACE="rh-ee-hongliu-tenant"
APPLICATION="test-group"

SNAPSHOT_NAME="snapshot-$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="${SNAPSHOT_NAME}.yaml"

COMPONENTS_JSON=$(kubectl get components -n $NAMESPACE -o json | jq --arg app "$APPLICATION" '
  [.items[] | select(.spec.application == $app)]' 2>/dev/null)

if [[ $? -ne 0 || -z "$COMPONENTS_JSON" ]]; then
    echo "Error: Failed to parse components JSON" >&2
    exit 1
fi

ARRAY_LENGTH=$(echo "$COMPONENTS_JSON" | jq 'length' 2>/dev/null)
if [[ $? -ne 0 || $ARRAY_LENGTH -eq 0 ]]; then
    echo "can't find any components in namespace $NAMESPACE for application $APPLICATION" >&2
    exit 1
fi

echo "Found $ARRAY_LENGTH components"

{
cat <<EOF
kind: Snapshot
metadata:
  name: $SNAPSHOT_NAME
  namespace: $NAMESPACE
  labels:
    test.appstudio.openshift.io/type: override
spec:
  application: $APPLICATION
  components:
EOF

# 使用更安全的jq处理
echo "$COMPONENTS_JSON" | jq -r '.[] | 
"    - name: \(.metadata.name)",
"      containerImage: \(.status."lastPromotedImage" // .spec."containerImage")",
"      source:",
"        git:",
"          url: \(.spec.source.git.url)",
"          revision: \(.status."lastBuiltCommit" // .spec.source.git.revision)"' 2>/dev/null

} > "$OUTPUT_FILE"

if [[ $? -eq 0 ]]; then
    echo "Snapshot content is generated and saved in: $OUTPUT_FILE"
else
    echo "Error: Failed to generate snapshot" >&2
    exit 1
fi

# generate snapshot after the script is ready
# kubectl apply -f $OUTPUT_FILE