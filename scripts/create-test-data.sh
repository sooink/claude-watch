#!/bin/bash
# Claude Watch test data creation script
#
# Usage:
#   ./scripts/create-test-data.sh          # Interactive mode
#   ./scripts/create-test-data.sh --auto   # Auto mode (no confirmation)
#   ./scripts/create-test-data.sh --clean  # Delete test data
#
# Test scenario:
#   1. Create subagent (running status, time increases)
#   2. Complete subagent (completed status, time stops)
#   3. Create and update task status
#   4. Delete session file (project removed)

set -e

CLAUDE_DIR="$HOME/.claude/projects"
PROJECT_HASH="-Users-test-claude-watch"
PROJECT_DIR="$CLAUDE_DIR/$PROJECT_HASH"

# Timestamp function
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.000Z"
}

# Cleanup function
cleanup() {
    echo "Cleaning up test data..."
    rm -rf "$PROJECT_DIR"
    echo "Done."
}

# --clean option
if [[ "$1" == "--clean" ]]; then
    cleanup
    exit 0
fi

# Check Claude process
FAKE_PID=""
if ! pgrep -x claude > /dev/null; then
    echo "WARNING: 'claude' process not running!"
    echo "Starting fake claude process..."
    bash -c 'exec -a claude sleep 3600' &
    FAKE_PID=$!
    echo "Started fake process (PID: $FAKE_PID)"
fi

# Cleanup on exit
trap_cleanup() {
    if [[ -n "$FAKE_PID" ]]; then
        kill $FAKE_PID 2>/dev/null || true
    fi
    cleanup
}
trap trap_cleanup EXIT

# Create session
SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
SESSION_FILE="$PROJECT_DIR/$SESSION_ID.jsonl"
mkdir -p "$PROJECT_DIR"

echo ""
echo "=========================================="
echo "Claude Watch Test Script"
echo "=========================================="
echo "Project: $PROJECT_DIR"
echo "Session: $SESSION_ID"
echo ""

# Wait function
wait_for_input() {
    if [[ "$1" != "--auto" ]]; then
        read -p "Press Enter to continue... " </dev/tty
    else
        sleep 2
    fi
}

# 1. Create initial session
echo "[Step 1] Creating session with cwd..."
cat > "$SESSION_FILE" << EOF
{"type":"system","timestamp":"$(timestamp)","cwd":"/Users/test/claude-watch-demo"}
EOF
sleep 2

# 2. Start Subagent 1
echo ""
echo "[Step 2] Starting Subagent 1 (Exploring codebase)..."
echo "  -> Check project and running subagent in app"
cat >> "$SESSION_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_agent1","name":"Task","input":{"description":"Exploring codebase","prompt":"Find all source files","subagent_type":"Explore"}}]}}
EOF
wait_for_input "$1"

# 3. Start Subagent 2
echo ""
echo "[Step 3] Starting Subagent 2 (Running tests)..."
echo "  -> Second running subagent added"
cat >> "$SESSION_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_agent2","name":"Task","input":{"description":"Running tests","prompt":"Execute test suite","subagent_type":"Bash"}}]}}
EOF
wait_for_input "$1"

# 4. Complete Subagent 1
echo ""
echo "[Step 4] Completing Subagent 1..."
echo "  -> 'Exploring codebase' changes to completed, time stops"
cat >> "$SESSION_FILE" << EOF
{"type":"user","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_agent1","content":"Found 42 source files in the codebase."}]}}
EOF
wait_for_input "$1"

# 5. Create Tasks
echo ""
echo "[Step 5] Creating Tasks..."
echo "  -> Task list appears"
cat >> "$SESSION_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_task1","name":"TaskCreate","input":{"subject":"Set up project structure","description":"Create directories","activeForm":"Setting up project"}}]}}
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_task2","name":"TaskCreate","input":{"subject":"Implement core features","description":"Build main functionality","activeForm":"Implementing features"}}]}}
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_task3","name":"TaskCreate","input":{"subject":"Write unit tests","description":"Add test coverage","activeForm":"Writing tests"}}]}}
EOF
wait_for_input "$1"

# 6. Update Task status
echo ""
echo "[Step 6] Updating Task status..."
echo "  -> Task 1 completed, Task 2 in_progress"
cat >> "$SESSION_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_update1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_update2","name":"TaskUpdate","input":{"taskId":"2","status":"in_progress"}}]}}
EOF
wait_for_input "$1"

# 7. Complete Subagent 2
echo ""
echo "[Step 7] Completing Subagent 2..."
echo "  -> 'Running tests' changes to completed, time stops"
cat >> "$SESSION_FILE" << EOF
{"type":"user","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_agent2","content":"All 15 tests passed successfully."}]}}
EOF
wait_for_input "$1"

# 8. Delete session file
echo ""
echo "[Step 8] Deleting session file..."
echo "  -> Project disappears from app"
rm -f "$SESSION_FILE"
rmdir "$PROJECT_DIR" 2>/dev/null || true

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="

# Release trap (already cleaned up)
trap - EXIT
if [[ -n "$FAKE_PID" ]]; then
    kill $FAKE_PID 2>/dev/null || true
fi
