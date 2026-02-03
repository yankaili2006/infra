#!/bin/bash
set -e

# Code Interpreter Template Builder for Local E2B
# This script builds the code-interpreter-v1 template using local E2B infrastructure

# 加载环境变量配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
source "$PCLOUD_HOME/config/env.sh" 2>/dev/null || true

BUILD_TOOL="$PCLOUD_HOME/infra/packages/orchestrator/bin/build-template"
TEMPLATE_NAME="code-interpreter-v1"

echo "=================================================="
echo "Building Code Interpreter Template for Local E2B"
echo "=================================================="
echo ""
echo "Template directory: $SCRIPT_DIR"
echo "Build tool: $BUILD_TOOL"
echo "Template name: $TEMPLATE_NAME"
echo ""

# Check if build-template exists
if [ ! -f "$BUILD_TOOL" ]; then
    echo "❌ Error: build-template not found at $BUILD_TOOL"
    echo "Please make sure E2B infrastructure is properly built"
    exit 1
fi

# Create a temporary Dockerfile
echo "📝 Creating Dockerfile from template.py..."

# Generate Dockerfile using Python
cd "$SCRIPT_DIR"

# Create a Dockerfile generator script
cat > generate_dockerfile.py << 'EOF'
#!/usr/bin/env python3
"""
Generate Dockerfile from template.py for local E2B build
"""

def dockerfile_from_template():
    """Convert E2B Template DSL to Dockerfile"""

    # Start with base image
    dockerfile = [
        "FROM python:3.12",
        "USER root",
        "WORKDIR /root",
        "",
        "# Environment variables",
        "ENV PIP_DEFAULT_TIMEOUT=100",
        "ENV PIP_DISABLE_PIP_VERSION_CHECK=1",
        "ENV PIP_NO_CACHE_DIR=1",
        "ENV JUPYTER_CONFIG_PATH=/root/.jupyter",
        "ENV IPYTHON_CONFIG_PATH=/root/.ipython",
        "ENV SERVER_PATH=/root/.server",
        "ENV JAVA_VERSION=11",
        "ENV JAVA_HOME=/usr/lib/jvm/jdk-${JAVA_VERSION}",
        "ENV IJAVA_VERSION=1.3.0",
        "ENV DENO_INSTALL=/opt/deno",
        "ENV DENO_VERSION=v2.4.0",
        "ENV R_VERSION=4.5.*",
        "",
        "# Install system dependencies",
        "RUN apt-get update && apt-get install -y \\",
        "    build-essential \\",
        "    curl \\",
        "    git \\",
        "    util-linux \\",
        "    jq \\",
        "    sudo \\",
        "    fonts-noto-cjk \\",
        "    ca-certificates \\",
        "    && rm -rf /var/lib/apt/lists/*",
        "",
        "# Install Node.js",
        "RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \\",
        "    apt-get install -y nodejs && \\",
        "    rm -rf /var/lib/apt/lists/*",
        "",
        "# Copy and install Python requirements",
        "COPY requirements.txt /root/requirements.txt",
        "RUN pip install --no-cache-dir -r /root/requirements.txt",
        "",
        "# Install Python kernel",
        "RUN ipython kernel install --name 'python3' --user",
        "",
        "# Install JavaScript Kernel",
        "RUN npm install -g --unsafe-perm git+https://github.com/e2b-dev/ijavascript.git && \\",
        "    ijsinstall --install=global",
        "",
        "# Create and setup server virtual environment",
        "COPY server /root/.server",
        "RUN python -m venv /root/.server/.venv && \\",
        "    /root/.server/.venv/bin/pip install --no-cache-dir -r /root/.server/requirements.txt",
        "",
        "# Copy configuration files",
        "COPY matplotlibrc /root/.config/matplotlib/.matplotlibrc",
        "COPY start-up.sh /root/.jupyter/start-up.sh",
        "RUN chmod +x /root/.jupyter/start-up.sh",
        "COPY jupyter_server_config.py /root/.jupyter/",
        "RUN mkdir -p /root/.ipython/profile_default/startup",
        "COPY ipython_kernel_config.py /root/.ipython/profile_default/",
        "COPY startup_scripts /root/.ipython/profile_default/startup",
        "",
        "# Create user account",
        "RUN useradd -m user && \\",
        "    mkdir -p /home/user && \\",
        "    chown -R user:user /home/user && \\",
        "    echo 'user ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers",
        "",
        "# Switch to user",
        "USER user",
        "WORKDIR /home/user",
        "",
        "# Start command",
        "CMD [\"sudo\", \"/root/.jupyter/start-up.sh\"]",
    ]

    return "\n".join(dockerfile)

if __name__ == "__main__":
    print(dockerfile_from_template())
EOF

python3 generate_dockerfile.py > Dockerfile

echo "✅ Dockerfile generated"
echo ""

# Build the template
echo "🏗️  Building template with build-template..."
echo ""

# Run build-template
# Note: Adjust parameters based on your build-template CLI
$BUILD_TOOL \
    --name "$TEMPLATE_NAME" \
    --dockerfile "$SCRIPT_DIR/Dockerfile" \
    --build-dir "$SCRIPT_DIR" \
    --output-dir "$PCLOUD_HOME/infra/storage/templates"

BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=================================================="
    echo "✅ Template built successfully!"
    echo "=================================================="
    echo ""
    echo "Template ID: $TEMPLATE_NAME"
    echo "You can now use this template with Fragments by setting:"
    echo "  E2B_API_URL=http://localhost:3000"
    echo "  template='code-interpreter-v1'"
    echo ""
else
    echo ""
    echo "=================================================="
    echo "❌ Template build failed"
    echo "=================================================="
    echo ""
    exit $BUILD_EXIT_CODE
fi
