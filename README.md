# Life Coach Claude - Sergeant Major MacTavish

This is a custom Claude Code configuration that implements a life coaching persona: **Sergeant Major Alistair "Ally" MacTavish (Ret.)**, a retired British Army warrant officer turned life coach.

## Overview

Ally is a gruff but warm Scottish life coach who combines military discipline with genuine compassion. He uses his 28 years of military experience to help people get their lives in order through practical, no-nonsense coaching.

## How It Works

The character and coaching approach are defined in `CLAUDE.md`, which serves as the primary instruction set for Claude Code when operating in this directory.

### Key Features

- **Character-driven coaching**: Consistent personality with Scottish expressions, military background, and specific coaching philosophy
- **Document integration**: Automatically reads and incorporates user-provided materials from the `docs/` folder
- **Accountability-focused**: Tracks commitments and follows up on previous conversations
- **Balanced approach**: Combines tough love with genuine warmth and psychological awareness

## The docs/ Folder

Place any PDFs, text files, or other documents in the `docs/` folder that you want Ally to review and incorporate into coaching sessions. These might include:

- Self-help books or excerpts
- Personal goal documents
- Articles on specific topics
- Session notes or reflections

**Ally will automatically read all documents in this folder at the start of each session.**

## Reference Materials

The following reference documents inform Ally's coaching approach:

- `scottish-slang.md` - Scottish expressions and slang for authentic character voice
- `coaching-principles.md` - Life coaching frameworks and techniques
- `character-background.md` - Full character backstory for consistency

(Note: These reference documents are mentioned in CLAUDE.md but may not all exist in the repository yet)

## Usage

Simply start Claude Code in this directory and begin your conversation. Ally will greet you and check in on your progress or discuss whatever you'd like to work on.

## Recent Changes

### 2025-11-28
- **Added SessionEnd Hook**: Automatic transcript export to `docs/{timestamp}.txt`
  - Configured `.claude/hooks.yaml` with SessionEnd hook
  - Automatically captures and saves full conversation transcripts when session ends
  - Transcripts formatted to match Claude Code UI style
  - No manual export needed - just exit session normally
  - Updated CLAUDE.md with documentation on automatic exports
- **Updated CLAUDE.md**: Made document reading mandatory at session start
  - Changed from "consider reading" to "MUST read ALL documents"
  - Ensures Ally has full context from user materials before each conversation
- **Created README.md**: Added project documentation

## Privacy

All documents and conversations are treated as confidential coaching materials.
