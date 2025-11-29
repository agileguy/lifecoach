#!/bin/bash

# Immediate marker file to prove hook ran
touch "/home/dan/lifecoach/HOOK_RAN_$(date +%s).marker"

# Debug logging - try direct write instead of exec redirect
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

  # Extract the conversation from JSONL format
  # Each line in JSONL is a complete JSON object
  while IFS= read -r line; do
    # Try to extract role and content from each message
    role=$(echo "$line" | jq -r '.role // ""')
    content=$(echo "$line" | jq -r '.content // ""')

    if [ "$role" = "user" ]; then
      echo "> $content"
      echo ""
    elif [ "$role" = "assistant" ]; then
      echo "● $content"
      echo ""
    fi
  done < "$TRANSCRIPT_PATH"

  echo ""
  echo ""
} > "$OUTPUT_FILE"

# Clean up temporary file
rm -f "$TEMP_JSON"

# Print confirmation message and log
echo "Session transcript saved to: $OUTPUT_FILE"
echo "[$(date)] Successfully created transcript at: $OUTPUT_FILE" >&2
