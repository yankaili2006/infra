#!/bin/bash
# Fragments Web UI Startup Script
# This script starts the Fragments web interface for E2B

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "  Starting Fragments Web UI for E2B"
echo "=========================================="
echo ""

# Check if E2B API is running
echo "1. Checking E2B API status..."
if curl -s -f http://localhost:3000/health > /dev/null 2>&1; then
    echo "   ✅ E2B API is running"
else
    echo "   ❌ E2B API is not running"
    echo ""
    echo "   Please start E2B infrastructure first:"
    echo "   cd $INFRA_DIR/local-deploy"
    echo "   ./scripts/start-all.sh"
    echo ""
    exit 1
fi

# Check if node_modules exists
echo ""
echo "2. Checking dependencies..."
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    echo "   ⚠️  Dependencies not installed"
    echo "   Installing dependencies (this may take a few minutes)..."
    cd "$SCRIPT_DIR"
    npm install
    echo "   ✅ Dependencies installed"
else
    echo "   ✅ Dependencies already installed"
fi

# Check if .env.local exists
echo ""
echo "3. Checking environment configuration..."
if [ ! -f "$SCRIPT_DIR/.env.local" ]; then
    echo "   ⚠️  .env.local not found, creating from template..."
    cp "$SCRIPT_DIR/.env.template" "$SCRIPT_DIR/.env.local"

    # Update with local E2B configuration
    sed -i 's|E2B_API_KEY=|E2B_API_KEY=e2b_53ae1fed82754c17ad8077fbc8bcdd90|' "$SCRIPT_DIR/.env.local"
    sed -i 's|E2B_BASE_URL=|E2B_BASE_URL=http://localhost:3000|' "$SCRIPT_DIR/.env.local"
    echo "   ✅ Environment configured"
else
    echo "   ✅ Environment already configured"
fi

# Start the development server
echo ""
echo "4. Starting Fragments development server..."
echo ""
echo "=========================================="
echo "  Fragments will be available at:"
echo "  http://localhost:3001"
echo ""
echo "  Press Ctrl+C to stop"
echo "=========================================="
echo ""

cd "$SCRIPT_DIR"
npm run dev
