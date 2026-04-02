#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELLO_API_DIR="kubernetes/resources/hello-api"

echo "Syncing hello-api with latest deployment files from git"

cd "$REPO_DIR"

# Fetch latest changes from origin
git fetch origin main

# Check if any hello-api deployment files have changed
if git diff --name-only HEAD origin/main | grep -q "$HELLO_API_DIR"; then
  echo "Changes detected in hello-api deployment files, pulling and applying..."
  
  git pull origin main
  
  # Apply all yaml files in the hello-api directory using replace --force
  # This ensures the cluster state matches git even if resources already exist
  for yaml_file in "$REPO_DIR/$HELLO_API_DIR"/*.yaml; do
    if [ -f "$yaml_file" ]; then
      echo "Applying $yaml_file..."
      kubectl replace --force -f "$yaml_file" || {
        echo "Replace failed, trying create..."
        kubectl create -f "$yaml_file" || echo "Warning: Failed to create $yaml_file"
      }
    fi
  done
  
  echo "Successfully synced hello-api deployment"
else
  echo "No changes detected in hello-api deployment files"
fi
