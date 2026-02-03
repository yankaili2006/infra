#!/bin/bash
##
# Fragments Test Suite Runner
#
# Runs all Fragments tests in sequence:
# 1. API tests
# 2. E2B integration tests
# 3. Playwright browser tests
#
# Usage:
#   ./run-all-tests.sh
#   ./run-all-tests.sh --verbose
#   ./run-all-tests.sh --skip-browser
#   ./run-all-tests.sh --screenshot
##

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Configuration
VERBOSE=""
SKIP_BROWSER=false
SCREENSHOT=""

# Parse arguments
for arg in "$@"; do
  case $arg in
    --verbose)
      VERBOSE="--verbose"
      ;;
    --skip-browser)
      SKIP_BROWSER=true
      ;;
    --screenshot)
      SCREENSHOT="--screenshot"
      ;;
    --help)
      echo "Fragments Test Suite Runner"
      echo ""
      echo "Usage:"
      echo "  ./run-all-tests.sh [options]"
      echo ""
      echo "Options:"
      echo "  --verbose       Show detailed test output"
      echo "  --skip-browser  Skip Playwright browser tests"
      echo "  --screenshot    Take screenshots during browser tests"
      echo "  --help          Show this help message"
      echo ""
      exit 0
      ;;
  esac
done

# Test script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test result files
API_RESULTS=""
E2B_RESULTS=""
PLAYWRIGHT_RESULTS=""

echo -e "${BOLD}=========================================="
echo "🧪 FRAGMENTS COMPREHENSIVE TEST SUITE"
echo -e "==========================================${RESET}"
echo -e "${CYAN}Test directory: $SCRIPT_DIR${RESET}"
echo -e "${CYAN}Project root:   $PROJECT_ROOT${RESET}"
echo ""

# Check prerequisites
echo -e "${BLUE}📋 Checking prerequisites...${RESET}"

# Check if Fragments is running
if curl -s -f http://localhost:3001 > /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${RESET} Fragments Web UI is running"
else
  echo -e "  ${RED}✗${RESET} Fragments Web UI is NOT running"
  echo -e "  ${YELLOW}  Start with: cd $PROJECT_ROOT && ./start-fragments.sh${RESET}"
  exit 1
fi

# Check if E2B API is running
if curl -s -f http://localhost:3000/health > /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${RESET} E2B API is running"
else
  echo -e "  ${RED}✗${RESET} E2B API is NOT running"
  echo -e "  ${YELLOW}  Start with: cd $PROJECT_ROOT/../local-deploy && ./scripts/start-all.sh${RESET}"
  exit 1
fi

# Check Node.js
if command -v node > /dev/null 2>&1; then
  NODE_VERSION=$(node --version)
  echo -e "  ${GREEN}✓${RESET} Node.js installed: $NODE_VERSION"
else
  echo -e "  ${RED}✗${RESET} Node.js is NOT installed"
  exit 1
fi

# Check Playwright (only if not skipping browser tests)
if [ "$SKIP_BROWSER" = false ]; then
  if node -e "require.resolve('playwright')" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} Playwright is installed"
  else
    echo -e "  ${YELLOW}⚠${RESET} Playwright is NOT installed"
    echo -e "  ${YELLOW}  Install with: npm install playwright && npx playwright install chromium${RESET}"
    echo -e "  ${YELLOW}  Or run with: ./run-all-tests.sh --skip-browser${RESET}"
    exit 1
  fi
fi

echo ""

# Function to run test and track results
run_test_suite() {
  local name=$1
  local script=$2
  local args=$3

  echo -e "${BOLD}=========================================="
  echo "🧪 Running: $name"
  echo -e "==========================================${RESET}"
  echo ""

  local start_time=$(date +%s)

  if node "$SCRIPT_DIR/$script" $args; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo -e "${GREEN}✅ $name PASSED${RESET} (${duration}s)"

    # Find and parse result file
    local result_file=$(ls -t /tmp/${script%.js}-results-*.json 2>/dev/null | head -1)
    if [ -f "$result_file" ]; then
      local passed=$(jq '.passed' "$result_file" 2>/dev/null || echo 0)
      local failed=$(jq '.failed' "$result_file" 2>/dev/null || echo 0)
      local total=$(jq '.total' "$result_file" 2>/dev/null || echo 0)

      TOTAL_TESTS=$((TOTAL_TESTS + total))
      PASSED_TESTS=$((PASSED_TESTS + passed))
      FAILED_TESTS=$((FAILED_TESTS + failed))

      # Store result file path
      case "$name" in
        *"API"*)
          API_RESULTS="$result_file"
          ;;
        *"E2B"*)
          E2B_RESULTS="$result_file"
          ;;
        *"Browser"*)
          PLAYWRIGHT_RESULTS="$result_file"
          ;;
      esac
    fi

    return 0
  else
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo -e "${RED}❌ $name FAILED${RESET} (${duration}s)"

    # Still count results if available
    local result_file=$(ls -t /tmp/${script%.js}-results-*.json 2>/dev/null | head -1)
    if [ -f "$result_file" ]; then
      local passed=$(jq '.passed' "$result_file" 2>/dev/null || echo 0)
      local failed=$(jq '.failed' "$result_file" 2>/dev/null || echo 0)
      local total=$(jq '.total' "$result_file" 2>/dev/null || echo 0)

      TOTAL_TESTS=$((TOTAL_TESTS + total))
      PASSED_TESTS=$((PASSED_TESTS + passed))
      FAILED_TESTS=$((FAILED_TESTS + failed))
    fi

    return 1
  fi
}

# Track overall success
OVERALL_SUCCESS=true

# Run API tests
echo ""
if run_test_suite "API Tests" "api-test-client.js" "$VERBOSE"; then
  :
else
  OVERALL_SUCCESS=false
fi

echo ""
echo ""

# Run E2B integration tests
if run_test_suite "E2B Integration Tests" "e2b-integration-test.js" "$VERBOSE"; then
  :
else
  OVERALL_SUCCESS=false
fi

echo ""
echo ""

# Run Playwright browser tests
if [ "$SKIP_BROWSER" = false ]; then
  if run_test_suite "Browser Tests" "playwright-test.js" "$SCREENSHOT"; then
    :
  else
    OVERALL_SUCCESS=false
  fi
else
  echo -e "${YELLOW}⏭️  Browser tests skipped${RESET}"
  SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
fi

# Final summary
echo ""
echo ""
echo -e "${BOLD}=========================================="
echo "📊 OVERALL TEST SUMMARY"
echo -e "==========================================${RESET}"
echo ""
echo -e "${CYAN}Total tests:   ${TOTAL_TESTS}${RESET}"
echo -e "${GREEN}✅ Passed:     ${PASSED_TESTS}${RESET}"
echo -e "${RED}❌ Failed:     ${FAILED_TESTS}${RESET}"
echo -e "${YELLOW}⏭️  Skipped:    ${SKIPPED_TESTS}${RESET}"
echo ""

# Calculate pass rate
if [ $TOTAL_TESTS -gt 0 ]; then
  PASS_RATE=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
  echo -e "${CYAN}Pass rate:     ${PASS_RATE}%${RESET}"
fi

echo -e "${BOLD}==========================================${RESET}"

# Result files
echo ""
echo -e "${BLUE}📄 Test result files:${RESET}"
[ -n "$API_RESULTS" ] && echo -e "  ${CYAN}API:        $API_RESULTS${RESET}"
[ -n "$E2B_RESULTS" ] && echo -e "  ${CYAN}E2B:        $E2B_RESULTS${RESET}"
[ -n "$PLAYWRIGHT_RESULTS" ] && echo -e "  ${CYAN}Browser:    $PLAYWRIGHT_RESULTS${RESET}"

# Screenshots (if taken)
if [ -d "/tmp/fragments-screenshots" ]; then
  SCREENSHOT_COUNT=$(ls -1 /tmp/fragments-screenshots/*.png 2>/dev/null | wc -l)
  if [ $SCREENSHOT_COUNT -gt 0 ]; then
    echo ""
    echo -e "${BLUE}📸 Screenshots: $SCREENSHOT_COUNT saved${RESET}"
    echo -e "  ${CYAN}/tmp/fragments-screenshots/${RESET}"
  fi
fi

echo ""

# Final result
if [ "$OVERALL_SUCCESS" = true ] && [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}${BOLD}🎉 ALL TESTS PASSED!${RESET}"
  echo ""
  exit 0
else
  echo -e "${RED}${BOLD}⚠️  SOME TESTS FAILED${RESET}"
  echo ""
  echo -e "${YELLOW}Review the test output above for details.${RESET}"
  echo -e "${YELLOW}Check individual result files for more information.${RESET}"
  echo ""
  exit 1
fi
