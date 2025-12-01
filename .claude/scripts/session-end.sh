#!/bin/bash

# Debug logging
LOG_FILE="/home/dan/lifecoach/hook-debug.log"
echo "[$(date)] ===== SessionEnd hook invoked =====" >> "$LOG_FILE" 2>&1
exec 2>>"$LOG_FILE"

# Log all environment variables that might be relevant
echo "[$(date)] Environment variables:" >&2
env | grep -i "claude\|session\|transcript" | sort >&2 || echo "  (none found)" >&2

# Create a temporary file to store the hook data
TEMP_JSON=$(mktemp)

# Read ALL stdin - wait for natural EOF (no timeout)
# This is more reliable than using timeout
cat > "$TEMP_JSON" 2>&1

# Get file size to check if we received data
FILE_SIZE=$(stat -c%s "$TEMP_JSON" 2>/dev/null || echo "0")
echo "[$(date)] Read $FILE_SIZE bytes from stdin" >&2

# Log the raw data received for debugging
echo "[$(date)] Raw stdin data:" >&2
cat "$TEMP_JSON" >&2
echo "[$(date)] --- End raw data ---" >&2

# If we got no data or very little data, something is wrong
if [ "$FILE_SIZE" -lt 10 ]; then
  echo "[$(date)] ERROR: Received insufficient data from stdin ($FILE_SIZE bytes)" >&2
  echo "[$(date)] This likely means Claude Code is not sending hook data properly" >&2
  rm -f "$TEMP_JSON"
  exit 1
fi

# Validate JSON before parsing
if ! jq empty < "$TEMP_JSON" 2>&1; then
  echo "[$(date)] ERROR: Invalid JSON received on stdin" >&2
  rm -f "$TEMP_JSON"
  exit 1
fi

echo "[$(date)] JSON validation passed" >&2

# Parse the JSON input from the file
SESSION_ID=$(jq -r '.session_id // "unknown"' < "$TEMP_JSON" 2>&1)
TRANSCRIPT_PATH=$(jq -r '.transcript_path // ""' < "$TEMP_JSON" 2>&1)
CWD=$(jq -r '.cwd // ""' < "$TEMP_JSON" 2>&1)
REASON=$(jq -r '.reason // "exit"' < "$TEMP_JSON" 2>&1)

echo "[$(date)] Parsed - SESSION_ID=$SESSION_ID, TRANSCRIPT_PATH=$TRANSCRIPT_PATH, CWD=$CWD, REASON=$REASON" >&2

# Change to the repository root directory
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD" || {
    echo "[$(date)] Warning: Failed to cd to $CWD" >&2
  }
  echo "[$(date)] Changed to directory: $CWD" >&2
else
  echo "[$(date)] Warning: CWD not set or not a directory: $CWD" >&2
fi

# Expand tilde in transcript path
TRANSCRIPT_PATH="${TRANSCRIPT_PATH/#\~/$HOME}"
echo "[$(date)] Expanded TRANSCRIPT_PATH=$TRANSCRIPT_PATH" >&2

# Generate timestamp
TIMESTAMP=$(date +"%Y-%m-%d-%H%M")

# Set output file path
DOCS_DIR="${CWD}/docs"
OUTPUT_FILE="${DOCS_DIR}/${TIMESTAMP}.txt"

# Ensure docs directory exists
mkdir -p "$DOCS_DIR" || true

# Check if transcript file exists
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "[$(date)] Warning: Transcript file not found at: $TRANSCRIPT_PATH" >&2
  rm -f "$TEMP_JSON"
  exit 0
fi

echo "[$(date)] Transcript file found, processing..." >&2

# Create the output file with header and conversation
{
  echo ""
  echo " ▐▛███▜▌   Claude Code v2.0.55"
  echo "▝▜█████▛▘  Sonnet 4.5 · Claude Pro"
  echo "  ▘▘ ▝▝    ~/lifecoach"
  echo ""

  # First pass: collect tool IDs that read from docs/ folder
  SKIP_IDS_FILE=$(mktemp)
  while IFS= read -r line; do
    echo "$line" | jq -r '
      .message.content[]? |
      select(.type == "tool_use" and .name == "Read") |
      select(.input.file_path | test("docs/.*\\.(md|txt)$")) |
      .id
    ' >> "$SKIP_IDS_FILE" 2>/dev/null
  done < "$TRANSCRIPT_PATH"

  # Extract the conversation from JSONL format with verbose mode details
  # Each line in JSONL is a complete JSON object
  while IFS= read -r line; do
    # Skip non-message lines (file-history-snapshot, summary, etc.)
    msg_type=$(echo "$line" | jq -r '.type // ""')
    if [ "$msg_type" != "user" ] && [ "$msg_type" != "assistant" ]; then
      continue
    fi

    # Extract the nested message object
    role=$(echo "$line" | jq -r '.message.role // ""')

    # Check if content is a string or array
    content_type=$(echo "$line" | jq -r '.message.content | type')

    if [ "$role" = "user" ]; then
      if [ "$content_type" = "string" ]; then
        # Simple string content
        content=$(echo "$line" | jq -r '.message.content')
        echo "> $content"
        echo ""
      else
        # Array of content blocks - handle tool_result, skip context doc results
        echo "$line" | jq -r '.message.content[] |
          if .type == "text" then
            "TEXT:" + .text
          elif .type == "tool_result" then
            "RESULT:" + .tool_use_id + ":END_ID:" + (.content | if type == "string" then . else tostring end)
          else
            empty
          end' | while IFS= read -r result_line; do
            if [[ "$result_line" == TEXT:* ]]; then
              echo "> ${result_line#TEXT:}"
            elif [[ "$result_line" == RESULT:* ]]; then
              tool_id=$(echo "$result_line" | sed 's/^RESULT:\([^:]*\):END_ID:.*/\1/')
              if ! grep -qF "$tool_id" "$SKIP_IDS_FILE" 2>/dev/null; then
                content=$(echo "$result_line" | sed 's/^RESULT:[^:]*:END_ID://')
                echo "○ [$tool_id] Result:"
                echo "$content"
              fi
            fi
          done
        echo ""
      fi
    elif [ "$role" = "assistant" ]; then
      if [ "$content_type" = "string" ]; then
        # Simple string content
        content=$(echo "$line" | jq -r '.message.content')
        echo "● $content"
        echo ""
      else
        # Array of content blocks - process each type, skip context doc reads
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
              echo "● ${content_line#TEXT:}"
            elif [[ "$content_line" == THINKING:* ]]; then
              echo "◆ Thinking:"
              echo "${content_line#THINKING:}"
            elif [[ "$content_line" == TOOL:* ]]; then
              tool_id=$(echo "$content_line" | sed 's/^TOOL:\([^:]*\):NAME:.*/\1/')
              tool_name=$(echo "$content_line" | sed 's/^TOOL:[^:]*:NAME:\([^:]*\):INPUT:.*/\1/')
              tool_input=$(echo "$content_line" | sed 's/^TOOL:[^:]*:NAME:[^:]*:INPUT://')

              # Check if this tool ID should be skipped
              if ! grep -qF "$tool_id" "$SKIP_IDS_FILE" 2>/dev/null; then
                echo "◇ Tool: $tool_name"
                echo "  Input: $tool_input"
              fi
            fi
          done
        echo ""
      fi
    fi
  done < "$TRANSCRIPT_PATH"

  # Clean up skip IDs temp file
  rm -f "$SKIP_IDS_FILE"

  echo ""
  echo ""
} > "$OUTPUT_FILE"

# Clean up temporary file
rm -f "$TEMP_JSON"

# Print confirmation message and log
echo "Session transcript saved to: $OUTPUT_FILE"
echo "[$(date)] Successfully created transcript at: $OUTPUT_FILE" >&2
