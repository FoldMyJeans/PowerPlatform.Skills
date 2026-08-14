---
name: powerapps-source-workflow
description: >-
  Work with Power Apps canvas app source as code: pa.yaml, pac canvas pack and unpack, the
  msapp file, solutions, and the app repo. Use whenever the user wants to edit pa.yaml, unpack
  or pack an msapp, export or import a canvas app, set up pac auth or the app repo layout, or
  hits the one way door (Studio only controls make pack fail app wide with PA2108). Trigger on
  "unpack the msapp", "pack the app", "pac canvas pack fails", "PA2108", "edit the pa.yaml",
  "export the canvas app", "set up pac", "one way door", "mirror the change into the repo".
  Assumes SharePoint backed canvas apps on standard Microsoft 365 licensing, no Dataverse.
---

# Power Apps source workflow

This skill covers the canvas source workflow: the pa.yaml source tree, packing and unpacking,
solutions, environment setup, and the git discipline for an app repo.

## When to use

Use this for anything touching app source files, pac commands, or the app repo. For the
formulas inside pa.yaml use `powerapps-powerfx`. For planning a whole new app and sequencing
the one way door use `powerapps-build-playbook`. For an error message check
`powerapps-troubleshooting` first.

## The one hard rule: respect the one way door

`pac canvas pack` is a one way door. Before writing YAML meant for packing, confirm the app
has no Studio only controls (people picker combos, attachment forms). If it does, packing
fails app wide (PA2108) and the workflow becomes Studio plus mirror: code goes to the human,
gets confirmed working in Studio, and only then is mirrored into the repo and committed.
Never advise packing an app past the door. `references/03_SOURCE_WORKFLOW.md` has the full
mechanics of both eras.

## Workflow

1. Establish which era the app is in. Era 1 (pre door): edit pa.yaml, pack, import. Era 2
   (post door): paste ready formulas to the human, confirm in Studio, mirror to the repo.
2. For era 1 edits, follow the source tree and pa.yaml anatomy in
   `references/03_SOURCE_WORKFLOW.md`, then run the build loop and the post import
   verification checklist.
3. For era 2, never commit unconfirmed changes. Paste first, confirm, then mirror.
4. All repo changes ride the pull request workflow in `references/02_ENVIRONMENT_SETUP.md`.
   No direct commits to main.

## References in this skill

- `references/03_SOURCE_WORKFLOW.md`: the one way door, the source tree, pa.yaml anatomy,
  the era 1 build loop, the era 2 mirror loop, solutions, and the verification checklist.
- `references/02_ENVIRONMENT_SETUP.md`: tools, pac auth, Windows gotchas, the pac commands
  that matter, repo layout, gitignore, the pull request workflow, and git discipline.
