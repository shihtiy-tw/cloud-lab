---
description: Convert existing tasks into vibe-kanban tasks for the feature based on available design artifacts.
tools: ['vibe_kanban_list_projects', 'vibe_kanban_create_task']
---

## User Input

```text
$ARGUMENTS
```

## Outline

1. **Setup**: Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list.
2. **Project Selection**:
   - Call `vibe_kanban_list_projects`.
   - Find the project with a name matching the current repository directory name (e.g., `kubernetes-lab`).
   - If multiple matches or no matches, prompt user for selection.
3. **Load User Stories**: Read `spec.md` from FEATURE_DIR.
4. **Task Creation**:
   - Parse each **User Story** from the `spec.md` file (sections starting with `### User Story`).
   - Extract the Spec ID from the `FEATURE_DIR` name (e.g., `001`).
   - For each User Story, call `vibe_kanban_create_task` with:
     - `project_id`: The identified project ID.
     - `title`: Standardized format: `Spec {Spec_ID}: {Priority}/US{N} {Story_Title}`.
       - **Example**: `Spec 001: P1/US1 Multi-Language Kernel Exploration`
     - `description`: The full text of the User Story section, including the "As a... I want... So that..." statement, Independent Test, and Acceptance Scenarios.
5. **Report**: Output the number of User Stories synchronized to the Kanban board.
