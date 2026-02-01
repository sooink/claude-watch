#!/bin/bash
# Claude Watch multi-project test script
#
# Usage:
#   ./scripts/create-multi-project.sh          # Interactive mode
#   ./scripts/create-multi-project.sh --auto   # Auto mode
#   ./scripts/create-multi-project.sh --clean  # Delete test data

set -e

CLAUDE_DIR="$HOME/.claude/projects"
PROJECT1_HASH="-Users-test-frontend-app"
PROJECT2_HASH="-Users-test-backend-api"
PROJECT1_DIR="$CLAUDE_DIR/$PROJECT1_HASH"
PROJECT2_DIR="$CLAUDE_DIR/$PROJECT2_HASH"

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.000Z"
}

cleanup() {
    echo "Cleaning up test data..."
    rm -rf "$PROJECT1_DIR" "$PROJECT2_DIR"
    echo "Done."
}

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

trap_cleanup() {
    if [[ -n "$FAKE_PID" ]]; then
        kill $FAKE_PID 2>/dev/null || true
    fi
    cleanup
}
trap trap_cleanup EXIT

# Create sessions
SESSION1_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
SESSION2_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
SESSION1_FILE="$PROJECT1_DIR/$SESSION1_ID.jsonl"
SESSION2_FILE="$PROJECT2_DIR/$SESSION2_ID.jsonl"
mkdir -p "$PROJECT1_DIR" "$PROJECT2_DIR"

echo ""
echo "=========================================="
echo "Claude Watch Multi-Project Test"
echo "=========================================="
echo "Project 1: frontend-app"
echo "Project 2: backend-api"
echo ""

wait_for_input() {
    if [[ "$1" != "--auto" ]]; then
        read -p "Press Enter to continue... " </dev/tty
    else
        sleep 2
    fi
}

# Step 1: Initialize two projects
echo "[Step 1] Creating two projects..."
cat > "$SESSION1_FILE" << EOF
{"type":"system","timestamp":"$(timestamp)","cwd":"/Users/test/frontend-app"}
EOF
cat > "$SESSION2_FILE" << EOF
{"type":"system","timestamp":"$(timestamp)","cwd":"/Users/test/backend-api"}
EOF
sleep 2

# Step 2: Project 1 - Start subagents
echo ""
echo "[Step 2] Project 1: Starting subagents..."
cat >> "$SESSION1_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_fe_agent1","name":"Task","input":{"description":"Building React components","prompt":"Create UI","subagent_type":"Explore"}}]}}
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_fe_agent2","name":"Task","input":{"description":"Running Vitest","prompt":"Run tests","subagent_type":"Bash"}}]}}
EOF
wait_for_input "$1"

# Step 3: Project 2 - Create tasks
echo ""
echo "[Step 3] Project 2: Creating tasks..."
cat >> "$SESSION2_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_be_task1","name":"TaskCreate","input":{"subject":"Set up database schema","description":"Create tables","activeForm":"Setting up database"}}]}}
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_be_task2","name":"TaskCreate","input":{"subject":"Implement REST endpoints","description":"Build API","activeForm":"Implementing endpoints"}}]}}
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_be_task3","name":"TaskCreate","input":{"subject":"Add authentication","description":"JWT auth","activeForm":"Adding authentication"}}]}}
EOF
wait_for_input "$1"

# Step 4: Project 2 - Start subagent
echo ""
echo "[Step 4] Project 2: Starting subagent..."
cat >> "$SESSION2_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_be_agent1","name":"Task","input":{"description":"Running database migrations","prompt":"Migrate DB","subagent_type":"Bash"}}]}}
EOF
wait_for_input "$1"

# Step 5: Project 1 - Create tasks
echo ""
echo "[Step 5] Project 1: Creating tasks..."
cat >> "$SESSION1_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_fe_task1","name":"TaskCreate","input":{"subject":"Create header component","description":"Navigation header","activeForm":"Creating header"}}]}}
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_fe_task2","name":"TaskCreate","input":{"subject":"Implement routing","description":"React Router setup","activeForm":"Setting up routing"}}]}}
EOF
wait_for_input "$1"

# Step 6: Project 2 - Update task status
echo ""
echo "[Step 6] Project 2: Updating task status..."
cat >> "$SESSION2_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_be_update1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_be_update2","name":"TaskUpdate","input":{"taskId":"2","status":"in_progress"}}]}}
EOF
wait_for_input "$1"

# Step 7: Project 1 - Complete first subagent
echo ""
echo "[Step 7] Project 1: Completing first subagent..."
cat >> "$SESSION1_FILE" << EOF
{"type":"user","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_fe_agent1","content":"Built 5 React components successfully."}]}}
EOF
wait_for_input "$1"

# Step 8: Project 2 - Complete subagent
echo ""
echo "[Step 8] Project 2: Completing subagent..."
cat >> "$SESSION2_FILE" << EOF
{"type":"user","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_be_agent1","content":"Database migrations completed."}]}}
EOF
wait_for_input "$1"

# Step 9: Project 1 - Update tasks and complete subagent
echo ""
echo "[Step 9] Project 1: Updating tasks and completing subagent..."
cat >> "$SESSION1_FILE" << EOF
{"type":"assistant","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_use","id":"toolu_fe_update1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
{"type":"user","timestamp":"$(timestamp)","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_fe_agent2","content":"All 24 tests passed."}]}}
EOF
wait_for_input "$1"

# Step 10: Cleanup
echo ""
echo "[Step 10] Deleting all session files..."
rm -f "$SESSION1_FILE" "$SESSION2_FILE"
rmdir "$PROJECT1_DIR" "$PROJECT2_DIR" 2>/dev/null || true

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="

trap - EXIT
if [[ -n "$FAKE_PID" ]]; then
    kill $FAKE_PID 2>/dev/null || true
fi
