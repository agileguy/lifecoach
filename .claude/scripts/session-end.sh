#!/bin/bash
#
# Session End Hook for Claude Code
# Automatically saves session transcripts to docs/ folder

# Enable strict error handling (commented out for compatibility)
# set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Tool configuration
TOOL_NAME="Claude"
CONFIG_DIR=".claude"

# Debug logging (uncomment if needed)
# LOG_FILE="$HOME/${TOOL_NAME,,}-session-hook-debug.log"
# exec 2>>"$LOG_FILE"
# echo "[$(date)] ===== SessionEnd hook invoked for $TOOL_NAME =====" >&2

echo "[$(date)] Running SessionEnd hook for $TOOL_NAME" >&2

# ============================================================================
# Helper Functions
# ============================================================================

# Portable file size calculation
get_file_size() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "freebsd"* ]]; then
        # macOS/BSD
        stat -f%z "$file" 2>/dev/null || echo "0"
    else
        # Linux/GNU
        stat -c%s "$file" 2>/dev/null || echo "0"
    fi
}

# Expand home directory in path
expand_path() {
    local path="$1"
    # Handle tilde expansion safely
    if [[ "$path" =~ ^~(/|$) ]]; then
        path="${HOME}${path#\~}"
    fi
    echo "$path"
}

# Validate and create directory
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        if ! mkdir -p "$dir" 2>&1; then
            echo "[$(date)] ERROR: Failed to create directory: $dir" >&2
            return 1
        fi
        echo "[$(date)] Created directory: $dir" >&2
    fi
    return 0
}

# ============================================================================
# Main Processing
# ============================================================================

# Create temporary file for stdin data
TEMP_JSON=$(mktemp) || {
    echo "[$(date)] ERROR: Failed to create temporary file" >&2
    exit 1
}

# Ensure cleanup on exit
trap 'rm -f "$TEMP_JSON"' EXIT

# Read stdin data (wait for EOF without timeout)
cat > "$TEMP_JSON" 2>&1

# Validate we received data
FILE_SIZE=$(get_file_size "$TEMP_JSON")
echo "[$(date)] Read $FILE_SIZE bytes from stdin" >&2

if [[ "$FILE_SIZE" -lt 10 ]]; then
    echo "[$(date)] ERROR: Received insufficient data ($FILE_SIZE bytes)" >&2
    echo "[$(date)] $TOOL_NAME may not be sending hook data properly" >&2
    exit 1
fi

# Log raw data for debugging (first 500 chars)
echo "[$(date)] Raw stdin preview:" >&2
head -c 500 "$TEMP_JSON" >&2
echo "" >&2
echo "[$(date)] --- End preview ---" >&2

# Validate JSON before parsing
if ! jq empty < "$TEMP_JSON" 2>&1; then
    echo "[$(date)] ERROR: Invalid JSON received from $TOOL_NAME" >&2
    exit 1
fi

echo "[$(date)] JSON validation passed" >&2

# ============================================================================
# Parse Hook Data
# ============================================================================

SESSION_ID=$(jq -r '.session_id // "unknown"' < "$TEMP_JSON" 2>&1)
TRANSCRIPT_PATH=$(jq -r '.transcript_path // ""' < "$TEMP_JSON" 2>&1)
CWD=$(jq -r '.cwd // ""' < "$TEMP_JSON" 2>&1)
REASON=$(jq -r '.reason // "exit"' < "$TEMP_JSON" 2>&1)

echo "[$(date)] Parsed metadata:" >&2
echo "  SESSION_ID: $SESSION_ID" >&2
echo "  TRANSCRIPT_PATH: $TRANSCRIPT_PATH" >&2
echo "  CWD: $CWD" >&2
echo "  REASON: $REASON" >&2

# Change to repository root
if [[ -n "$CWD" ]] && [[ -d "$CWD" ]]; then
    cd "$CWD" || {
        echo "[$(date)] Warning: Failed to cd to $CWD" >&2
    }
    echo "[$(date)] Working directory: $CWD" >&2
else
    echo "[$(date)] Warning: Invalid or missing CWD: $CWD" >&2
    CWD="$(pwd)"
fi

# Expand transcript path
TRANSCRIPT_PATH=$(expand_path "$TRANSCRIPT_PATH")
echo "[$(date)] Expanded transcript path: $TRANSCRIPT_PATH" >&2

# ============================================================================
# Setup Output File
# ============================================================================

# Generate unique timestamp (with seconds to prevent collisions)
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")

# Add session ID to filename if available for extra uniqueness
if [[ -n "$SESSION_ID" ]] && [[ "$SESSION_ID" != "unknown" ]]; then
    SESSION_SUFFIX="-${SESSION_ID:0:8}"
else
    SESSION_SUFFIX=""
fi

# Set output paths
DOCS_DIR="${CWD}/docs"
OUTPUT_FILE="${DOCS_DIR}/${TIMESTAMP}${SESSION_SUFFIX}.txt"

# Ensure docs directory exists
if ! ensure_directory "$DOCS_DIR"; then
    echo "[$(date)] ERROR: Cannot create docs directory" >&2
    exit 1
fi

# ============================================================================
# Validate Transcript
# ============================================================================

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    echo "[$(date)] ERROR: Transcript file not found: $TRANSCRIPT_PATH" >&2
    echo "[$(date)] Cannot export session transcript" >&2
    exit 1
fi

echo "[$(date)] Transcript file found, processing..." >&2

# ============================================================================
# Generate Formatted Transcript
# ============================================================================

{
    echo ""
    echo " ▐▛███▜▌   $TOOL_NAME Code Session"
    echo "▝▜█████▛▘  Sonnet 4.5 · Code Assistant"
    echo "  ▘▘ ▝▝    Python Expert"
    echo ""
    echo "Session ID: $SESSION_ID"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Tool: $TOOL_NAME"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # First pass: collect tool IDs that read from docs/ folder
    # (Skip these from output to avoid clutter)
    SKIP_IDS_FILE=$(mktemp)
    trap 'rm -f "$TEMP_JSON" "$SKIP_IDS_FILE"' EXIT

    while IFS= read -r line; do
        echo "$line" | jq -r '
            .message.content[]? |
            select(.type == "tool_use" and .name == "Read") |
            select(.input.path | test("docs/.*\\.(md|txt)$")) |
            .id
        ' >> "$SKIP_IDS_FILE" 2>/dev/null || true
    done < "$TRANSCRIPT_PATH"

    # Extract and format conversation from JSONL
    while IFS= read -r line; do
        # Skip non-message lines
        msg_type=$(echo "$line" | jq -r '.type // ""')
        if [[ "$msg_type" != "user" ]] && [[ "$msg_type" != "assistant" ]]; then
            continue
        fi

        # Extract role and content
        role=$(echo "$line" | jq -r '.message.role // ""')
        content_type=$(echo "$line" | jq -r '.message.content | type')

        if [[ "$role" == "user" ]]; then
            if [[ "$content_type" == "string" ]]; then
                # Simple string content
                content=$(echo "$line" | jq -r '.message.content')
                echo "╭─ USER"
                echo "│"
                echo "$content" | sed 's/^/│ /'
                echo "│"
                echo "╰─"
                echo ""
            else
                # Array content with tool results
                echo "╭─ USER"
                echo "│"
                echo "$line" | jq -r '.message.content[] |
                    if .type == "text" then
                        "TEXT:" + .text
                    elif .type == "tool_result" then
                        "RESULT:" + .tool_use_id + ":END_ID:" + (.content | if type == "string" then . else tostring end)
                    else
                        empty
                    end' | while IFS= read -r result_line; do
                    if [[ "$result_line" == TEXT:* ]]; then
                        echo "${result_line#TEXT:}" | sed 's/^/│ /'
                    elif [[ "$result_line" == RESULT:* ]]; then
                        tool_id="${result_line#RESULT:}"
                        tool_id="${tool_id%%:END_ID:*}"
                        if ! grep -qF "$tool_id" "$SKIP_IDS_FILE" 2>/dev/null; then
                            content="${result_line#*:END_ID:}"
                            echo "│"
                            echo "│ ○ Tool Result [$tool_id]:" 
                            echo "$content" | head -20 | sed 's/^/│   /'
                            # Truncate long results
                            line_count=$(echo "$content" | wc -l)
                            if [[ "$line_count" -gt 20 ]]; then
                                echo "│   ... ($(( line_count - 20 )) more lines)"
                            fi
                        fi
                    fi
                done
                echo "│"
                echo "╰─"
                echo ""
            fi

        elif [[ "$role" == "assistant" ]]; then
            if [[ "$content_type" == "string" ]]; then
                # Simple string content
                content=$(echo "$line" | jq -r '.message.content')
                echo "╭─ ASSISTANT"
                echo "│"
                echo "$content" | sed 's/^/│ /'
                echo "│"
                echo "╰─"
                echo ""
            else
                # Array content with text, thinking, and tool use
                echo "╭─ ASSISTANT"
                echo "│"
                echo "$line" | jq -r '.message.content[] |
                    if .type == "text" then
                        "TEXT:" + .text
                    elif .type == "thinking" then
                        "THINKING:" + .thinking
                    elif .type == "tool_use" then
                        "TOOL:" + .id + ":NAME:" + .name + ":INPUT:" + (.input | tostring)
                    else
                        empty
                    end' | while IFS= read -r content_line; do
                    if [[ "$content_line" == TEXT:* ]]; then
                        echo "${content_line#TEXT:}" | sed 's/^/│ /'
                    elif [[ "$content_line" == THINKING:* ]]; then
                        echo "│"
                        echo "│ ◆ Thinking:"
                        echo "${content_line#THINKING:}" | sed 's/^/│   /'
                    elif [[ "$content_line" == TOOL:* ]]; then
                        tool_id="${content_line#TOOL:}"
                        tool_id="${tool_id%%:NAME:*}"
                        
                        # Skip if in skip list
                        if grep -qF "$tool_id" "$SKIP_IDS_FILE" 2>/dev/null; then
                            continue
                        fi
                        
                        temp="${content_line#*:NAME:}"
                        tool_name="${temp%%:INPUT:*}"
                        tool_input="${temp#*:INPUT:}"
                        
                        echo "│"
                        echo "│ ◇ Tool: $tool_name"
                        echo "Input: $tool_input" | head -5 | sed 's/^/│   /'
                    fi
                done
                echo "│"
                echo "╰─"
                echo ""
            fi
        fi
    done < "$TRANSCRIPT_PATH"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Session ended: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Reason: $REASON"
    echo ""

} > "$OUTPUT_FILE"

# ============================================================================
# Completion
# ============================================================================

echo "" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "✓ Session transcript saved to: $OUTPUT_FILE" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "" >&2

echo "[$(date)] Successfully created transcript at: $OUTPUT_FILE" >&2
exit 0
