#!/bin/bash

set -euo pipefail


# -------- Prompt for Inputs -------- #
read -rp "Enter Helm repo name (e.g., prometheus-community): " REPO_NAME
read -rp "Enter Helm chart name (e.g., cloudwatch-exporter): " CHART_NAME
read -rp "Enter Helm release name (e.g., cloudwatch-exporter): " RELEASE_NAME
read -rp "Enter Kubernetes namespace (e.g., default): " NAMESPACE
CHART_REPO_URL="https://$REPO_NAME.github.io/helm-charts"

# -------- Create Working Directory for Chart -------- #
CHART_WORKDIR="./$CHART_NAME"
mkdir -p "$CHART_WORKDIR"
cd "$CHART_WORKDIR"

# -------- Add and Update Helm Repo -------- #
echo "Adding and updating Helm repo..."
helm repo add "$REPO_NAME" "$CHART_REPO_URL" >/dev/null 2>&1 || true
helm repo update

# -------- List Last 5 Chart Versions -------- #
echo -e "\n Last 5 available versions for $CHART_NAME:"
VERSIONS=$(helm search repo "$REPO_NAME/$CHART_NAME" --versions | head -n 6)

if [[ $(echo "$VERSIONS" | wc -l) -le 1 ]]; then
  echo "No chart versions found for '$CHART_NAME' in repo '$REPO_NAME'. Exiting."
  exit 1
fi

echo "$VERSIONS"


# -------- Prompt for Chart Version -------- #
read -rp $'\n💡 Which version would you like to download?: ' SELECTED_VERSION

# -------- Get Current Deployed Version -------- #
echo -e "\n Detecting current deployed version..."
CURRENT_VERSION=$(helm list -n "$NAMESPACE" -f "$RELEASE_NAME" -o json | jq -r '.[0].chart' | sed "s/^$CHART_NAME-//")

if [[ -n "$CURRENT_VERSION" && "$CURRENT_VERSION" != "null" ]]; then
  echo " Current deployed version: $CURRENT_VERSION"
  mkdir -p "${CHART_NAME}-${CURRENT_VERSION}"
  mv "latest/${CHART_NAME}" "${CHART_NAME}-${CURRENT_VERSION}" 2>/dev/null || echo " No existing chart found in latest/ ."
else
  echo "No deployed release found or not installed in namespace '$NAMESPACE'."
fi

# -------- Download Requested Version -------- #
echo -e "\n Downloading $CHART_NAME version $SELECTED_VERSION..."
rm -rf latest && mkdir -p latest
cd latest
helm pull "$REPO_NAME/$CHART_NAME" --version "$SELECTED_VERSION" --untar
cd ..

# -------- Helm Lint -------- #
echo -e "\n Running helm lint..."
if ! helm lint "latest/$CHART_NAME"; then
  echo "Lint failed. Exiting."
  exit 1
fi

# -------- Render Template to Specific File -------- #
TEMPLATE_DIR="helm-template"
mkdir -p "$TEMPLATE_DIR"
TEMPLATE_FILE="$TEMPLATE_DIR/helm-template-${SELECTED_VERSION}.yaml"

echo -e "\n Rendering Helm template to $TEMPLATE_FILE"
helm template "$RELEASE_NAME" "latest/$CHART_NAME" > "$TEMPLATE_FILE"

# -------- Deploy to Kubernetes -------- #
echo -e "\n Deploying chart to Kubernetes..."
helm upgrade --install "$RELEASE_NAME" "latest/$CHART_NAME" -n "$NAMESPACE" --create-namespace


# -------- Print Status -------- #
echo -e "\n Checking release status:"
helm status "$RELEASE_NAME" -n "$NAMESPACE"

echo -e "\n Done:"
echo "   - Chart version $SELECTED_VERSION is downloaded in ./latest/$CHART_NAME"
echo "   - Archived old chart (if found) in ./archived/"
echo "   - Rendered template saved to: $TEMP_DIR/rendered.yaml"

