#!/bin/bash
# Claude Watch Hook Event Test Script
# Usage: ./scripts/test-hook-events.sh [path]
#
# If path is not specified, uses the current directory.
# Use an actual Claude Code session path to see UI indicator changes.

set -e

SOCKET_PATH="/tmp/claude-watch.sock"
TEST_CWD="${1:-$(pwd)}"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "  Claude Watch Hook Event Test"
echo "========================================"
echo ""
echo -e "Test path: ${BLUE}$TEST_CWD${NC}"
echo ""

# 1. Check socket exists
echo -n "1. Checking socket file... "
if [ -S "$SOCKET_PATH" ]; then
    echo -e "${GREEN}OK${NC} ($SOCKET_PATH)"
else
    echo -e "${RED}FAIL${NC}"
    echo "   Socket not found. Enable Hook in Claude Watch."
    echo "   Settings > Enable Hook Integration"
    exit 1
fi

# 2. Send UserPromptSubmit event
SESSION_ID="test-$$-$(date +%s)"
echo -n "2. Sending UserPromptSubmit event... "
PAYLOAD="{\"event\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$TEST_CWD\"}"
echo -e "${YELLOW}payload: $PAYLOAD${NC}"
RESULT=$(echo "$PAYLOAD" | nc -U "$SOCKET_PATH" 2>&1)
if [ $? -eq 0 ]; then
    echo -e "   ${GREEN}OK${NC}"
else
    echo -e "   ${RED}FAIL${NC}"
    echo "   $RESULT"
    exit 1
fi

# 3. Wait
echo -n "3. Waiting 3 seconds... "
echo -e "${YELLOW}(Check for green blinking indicator in Claude Watch UI)${NC}"
sleep 3
echo -e "   ${GREEN}OK${NC}"

# 4. Send PreToolUse(Task) event
TOOL_USE_ID="toolu-test-$(date +%s)"
echo -n "4. Sending PreToolUse(Task) event... "
PAYLOAD="{\"event\":\"PreToolUse\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$TEST_CWD\",\"tool_name\":\"Task\",\"tool_use_id\":\"$TOOL_USE_ID\",\"tool_input\":{\"description\":\"Hook test subagent\",\"subagent_type\":\"Explore\"}}"
echo -e "${YELLOW}payload: $PAYLOAD${NC}"
RESULT=$(echo "$PAYLOAD" | nc -U "$SOCKET_PATH" 2>&1)
if [ $? -eq 0 ]; then
    echo -e "   ${GREEN}OK${NC}"
else
    echo -e "   ${RED}FAIL${NC}"
    echo "   $RESULT"
    exit 1
fi

# 5. Wait
echo -n "5. Waiting 2 seconds... "
echo -e "${YELLOW}(Check for subagent running row in Claude Watch UI)${NC}"
sleep 2
echo -e "   ${GREEN}OK${NC}"

# 6. Send PostToolUse(Task) event
echo -n "6. Sending PostToolUse(Task) event... "
PAYLOAD="{\"event\":\"PostToolUse\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$TEST_CWD\",\"tool_name\":\"Task\",\"tool_use_id\":\"$TOOL_USE_ID\"}"
echo -e "${YELLOW}payload: $PAYLOAD${NC}"
RESULT=$(echo "$PAYLOAD" | nc -U "$SOCKET_PATH" 2>&1)
if [ $? -eq 0 ]; then
    echo -e "   ${GREEN}OK${NC}"
else
    echo -e "   ${RED}FAIL${NC}"
    echo "   $RESULT"
    exit 1
fi

# 7. Send another PreToolUse(Task) event for failure case
TOOL_USE_ID_FAIL="toolu-test-fail-$(date +%s)"
echo -n "7. Sending PreToolUse(Task) event (failure case)... "
PAYLOAD="{\"event\":\"PreToolUse\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$TEST_CWD\",\"tool_name\":\"Task\",\"tool_use_id\":\"$TOOL_USE_ID_FAIL\",\"tool_input\":{\"description\":\"Hook fail subagent\",\"subagent_type\":\"Bash\"}}"
echo -e "${YELLOW}payload: $PAYLOAD${NC}"
RESULT=$(echo "$PAYLOAD" | nc -U "$SOCKET_PATH" 2>&1)
if [ $? -eq 0 ]; then
    echo -e "   ${GREEN}OK${NC}"
else
    echo -e "   ${RED}FAIL${NC}"
    echo "   $RESULT"
    exit 1
fi

# 8. Send PostToolUseFailure(Task) event
echo -n "8. Sending PostToolUseFailure(Task) event... "
PAYLOAD="{\"event\":\"PostToolUseFailure\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$TEST_CWD\",\"tool_name\":\"Task\",\"tool_use_id\":\"$TOOL_USE_ID_FAIL\"}"
echo -e "${YELLOW}payload: $PAYLOAD${NC}"
RESULT=$(echo "$PAYLOAD" | nc -U "$SOCKET_PATH" 2>&1)
if [ $? -eq 0 ]; then
    echo -e "   ${GREEN}OK${NC}"
else
    echo -e "   ${RED}FAIL${NC}"
    echo "   $RESULT"
    exit 1
fi

# 9. Send Stop event
echo -n "9. Sending Stop event... "
PAYLOAD="{\"event\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$TEST_CWD\"}"
echo -e "${YELLOW}payload: $PAYLOAD${NC}"
RESULT=$(echo "$PAYLOAD" | nc -U "$SOCKET_PATH" 2>&1)
if [ $? -eq 0 ]; then
    echo -e "   ${GREEN}OK${NC}"
else
    echo -e "   ${RED}FAIL${NC}"
    echo "   $RESULT"
    exit 1
fi

echo ""
echo "========================================"
echo -e "  ${GREEN}All tests passed!${NC}"
echo "========================================"
echo ""
echo "Results:"
echo "  - Socket communication: Success"
echo ""
echo -e "${YELLOW}Expected UI behavior:${NC}"
echo "  - UserPromptSubmit: Green blinking indicator appears (working)"
echo "  - PreToolUse(Task): New subagent appears as running"
echo "  - PostToolUse(Task): Same subagent changes to completed"
echo "  - PostToolUseFailure(Task): Same subagent changes to error"
echo "  - Stop: Indicator turns gray (idle)"
echo ""
