---
name: powerapps-source-workflow
description: >-
  Work with Power Apps canvas app source as code: pa.yaml, pac canvas pack and unpack, the
  msapp file, shipping a packed app through an app-only solution with the AppId kept, restoring
  people picker search after a source ship, and the app repo. Use whenever the user wants to
  edit pa.yaml, unpack or pack an msapp, restyle or rebuild an app from source, export or import
  a canvas app, set up pac auth or the app repo layout, or has people pickers (Classic ComboBox)
  that find nobody when typing after an import. Trigger on "unpack the msapp", "pack the app",
  "ship the app from source", "pac canvas pack", "PA2108", "SearchItems", "people picker search
  broken", "edit the pa.yaml", "export the canvas app", "set up pac", "pull the app into the
  repo". Assumes SharePoint backed canvas apps on standard Microsoft 365 licensing, no Dataverse.
---

# Power Apps source workflow

This skill covers the canvas source workflow: the pa.yaml source tree, packing and unpacking,
shipping from source, solutions, environment setup, and the git discipline for an app repo.

## When to use

Use this for anything touching app source files, pac commands, or the app repo. For the
formulas inside pa.yaml use `powerapps-powerfx`. For planning a whole new app use
`powerapps-build-playbook`. For an error message check `powerapps-troubleshooting` first.

## The one hard rule: SearchItems never goes in source

The whole app packs from source, people pickers and attachment forms included. The one thing
source cannot carry is a `Classic/ComboBox`'s `SearchItems`. Unpack omits it, Studio's YAML
loader rejects it (PA2108), and Studio's Advanced pane does not expose it. Never try to fix
picker search in YAML or Studio. After every ship, restore it in the published msapp with
`scripts/fix_picker_search.py`. Every other formula survives a source ship.

## Workflow

1. Start from source that matches the live app. If the repo is not current, or the app was
   built in Studio, `pac canvas download` then `pac canvas unpack --layout SourceCode`.
2. Edit `Src/*.pa.yaml` against the source tree and anatomy in `references/source-workflow.md`.
   Pack with `pac canvas pack --sources <src> --msapp build.msapp`.
3. Before a big ship, load the msapp into a throwaway copy in Studio (Import app from file,
   never Save). Pack does not validate property names, YAML syntax, or Power Fx.
4. Ship through the app-only solution, keeping the AppId. The canonical procedure is
   "Shipping from source" in `references/source-workflow.md`. In short:
   - Export the app solution, swap in the build msapp, bump `<Version>`, zip, import with
     `--async --publish-changes --force-overwrite`.
   - If the app has people pickers: open it in Studio and Publish, `pac canvas download`,
     `python scripts/fix_picker_search.py live.msapp fixed.msapp`, swap `fixed.msapp` in the
     same way (bump `<Version>` again), import.
   - Verify: download again, the script in report mode prints `0 change(s), 0 manual`, and a
     typed name finds a person in Play mode.
5. On a live app, run the ship back to back in a quiet window. Pickers have no search
   between the first import and the fixed one.
6. A handful of formula changes can still be pasted into Studio. Publish, then pull the app
   into the repo and commit before anyone edits source again.
7. All repo changes ride the pull request workflow in `references/environment-setup.md`.
   No direct commits to main.

## Scripts in this skill

- `scripts/fix_picker_search.py`: rewrites each combo's `SearchItems` in a Studio published
  msapp from its own `Items: Choices(<List>.<PersonColumn>)`. Report mode with one argument,
  writes a fixed copy with two, `--selftest` to check it. Python 3, standard library only.

## References in this skill

- `references/source-workflow.md`: what pack can and cannot carry, the source tree, pa.yaml
  anatomy with a people picker example, the dev loop, the shipping procedure, small Studio
  edits, the two solutions, delete and reimport facts, ownership, and the verification checklist.
- `references/environment-setup.md`: tools, pac auth, Windows gotchas, the pac commands
  that matter, repo layout, gitignore, the pull request workflow, and git discipline.
