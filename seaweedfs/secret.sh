#!/bin/bash
set -euo pipefail  # Add this for better error handling

if ! kubectl get namespace seaweedfs >/dev/null 2>&1; then
    echo "Error: namespace 'seaweedfs' does not exist"
    exit 1
fi

if ! kubectl get namespace mlflow-tracking >/dev/null 2>&1; then
    echo "Error: namespace 'mlflow-tracking' does not exist"
    exit 1
fi

if ! openssl version >/dev/null 2>&1; then
    echo "Error: openssl is not installed"
    exit 1
fi

# Generate admin credentials
ADMIN_ACCESS_KEY=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
ADMIN_SECRET_KEY=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | cut -c1-32)

# Generate read-only credentials 
READONLY_ACCESS_KEY=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
READONLY_SECRET_KEY=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | cut -c1-32)

# Create secret yaml
cat > my-s3-secret.yaml << EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
 name: my-s3-secret
 namespace: seaweedfs 
 labels:
   app.kubernetes.io/name: seaweedfs
   app.kubernetes.io/component: s3
stringData:
 seaweedfs_s3_config: '{"identities":[{"name":"Admin","credentials":[{"accessKey":"$ADMIN_ACCESS_KEY","secretKey":"$ADMIN_SECRET_KEY"}],"actions":["Admin","Read","Write"]},{"name":"ReadOnly","credentials":[{"accessKey":"$READONLY_ACCESS_KEY","secretKey":"$READONLY_SECRET_KEY"}],"actions":["Read"]}]}'
EOF

# Crate another secret yaml to be used by the mlflow deployment
cat > s3-secret-deployment.yaml << EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
 name: s3-secret-deployment
 namespace: mlflow-tracking 
stringData:
  AWS_ACCESS_KEY_ID: $ADMIN_ACCESS_KEY
  AWS_SECRET_ACCESS_KEY: $ADMIN_SECRET_KEY
EOF

# Apply the secrets
kubectl apply -f my-s3-secret.yaml
kubectl apply -f s3-secret-deployment.yaml

# Print credentials
echo -e "\nAdmin Credentials:"
echo "Access Key: $ADMIN_ACCESS_KEY"
echo "Secret Key: $ADMIN_SECRET_KEY"

echo -e "\nRead-only Credentials:"
echo "Access Key: $READONLY_ACCESS_KEY"
echo "Secret Key: $READONLY_SECRET_KEY"
