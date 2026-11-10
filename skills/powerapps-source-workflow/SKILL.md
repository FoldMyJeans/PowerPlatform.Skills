---
name: powerapps-source-workflow
description: >-
  Work with Power Apps canvas app source as code: pa.yaml, pac canvas pack and unpack, the
  msapp file, shipping a packed app through an app-only solution with the AppId kept, people
  picker search after a source ship, solutions, ownership, test copies, and the app repo. Use
  whenever the user wants to edit pa.yaml, unpack or pack an msapp, restyle or rebuild an app
  from source, export or import a canvas app, delete a solution, move app ownership to a
  service account, set up a test copy, set up pac auth or the app repo layout, or has people
  pickers (Classic ComboBox) that show blank rows or find nobody after an import. Trigger on
  "unpack the msapp", "pack the app", "ship the app from source", "pac canvas pack",
  "pac canvas download", "PA2108", "PA1001", "SearchItems", "people picker search broken",
  "edit the pa.yaml", "export the canvas app", "set up pac", "pull the app into the repo",
  "canvas authoring MCP", "compile_canvas".
  Assumes SharePoint backed canvas apps on standard Microsoft 365 licensing, no Dataverse.
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
loader rejects it (PA2108), and whatever compiles the YAML writes a template that finds
nobody. Never try to fix picker search in YAML or Studio. Either restore it in the published
msapp with `scripts/fix_picker_search.py` after every ship, or build the picker as a non
searchable combo fed by a text input, which needs no fix. Every other formula survives a
source ship.

## Pick the path

| Change | Path |
|---|---|
| A handful of formula edits | Paste in Studio, publish, pull into the repo (step 6) |
| New controls, a restyle, anything in more than a few places | Edit source and ship (steps 1 to 5) |
| The app has searchable Classic people pickers | Every source ship also runs the picker fix. Or switch them to the two box picker once |
| A brand new app, never in the cloud | First import in Studio, data sources, then the app-only solution (the `powerapps-build-playbook` skill, manual steps). Every ship after that follows this skill |

## Workflow

1. Start from source that matches the live app. If the repo is not current, or the app was
   built in Studio, `pac canvas download` then `pac canvas unpack --layout SourceCode`.
2. Edit `Src/*.pa.yaml` against the source tree and anatomy in `references/source-workflow.md`.
   Pack with `pac canvas pack --sources <src> --msapp build.msapp --layout SourceCode`.
3. Before every ship, load the msapp into a throwaway copy in Studio (Import app from file,
   never Save). Pack does not validate property names, YAML syntax, or Power Fx. Clear any
   load error (PA1001, PA2108, PA1011) before anything else, the picker fix needs Studio to
   open and publish the app.
4. Ship through the app-only solution, keeping the AppId. The canonical procedure is
   "Shipping from source" in `references/source-workflow.md`. In short:
   - Close every Studio tab of the app first. Export the app solution, swap in the build
     msapp, bump `<Version>`, zip, import with `--async --publish-changes --force-overwrite`.
     The app is live for users the moment the import lands.
   - If the app has searchable people pickers: open it in Studio, confirm a control you added
     is in the tree view, and Publish. `pac canvas download --name <AppId>`,
     `python scripts/fix_picker_search.py live.msapp fixed.msapp`, swap `fixed.msapp` in the
     same way (bump `<Version>` again), import. `0 change(s)` from that script right after a
     publish means the publish was not your build, so stop.
   - Verify: download again, the script in report mode prints `0 change(s), 0 manual`, and a
     typed name finds a person in Play mode.
5. On a live app, run the ship back to back in a quiet window and do not pause. Searchable
   pickers are broken for every user between the first import and the fixed one.
6. A handful of formula changes can still be pasted into Studio. Publish, then pull the app
   into the repo and commit before anyone edits source again.
7. All repo changes ride the pull request workflow in `references/environment-setup.md`.
   No direct commits to main.

## Scripts in this skill

- `scripts/fix_picker_search.py`: rewrites each searchable combo's `SearchItems` in a Studio
  published msapp from its own `Items: Choices(<List>.<PersonColumn>)`. Report mode with one
  argument, writes a fixed copy with two, `--selftest` to check it. Python 3, standard
  library only.

## References in this skill

- `references/source-workflow.md`: what pack can and cannot carry, the two ways out for
  picker search, the source tree, pa.yaml anatomy with people picker examples, the dev loop,
  the shipping procedure, small Studio edits, the verification checklist, where the canvas
  authoring MCP fits, and driving Studio from a browser tool.
- `references/solutions-and-ownership.md`: the app-only and flow solutions, what survives a
  delete and reimport, deleting a solution for real, moving ownership to a service account,
  and generating a test copy of the app and flows.
- `references/environment-setup.md`: tools, pac auth, Windows gotchas, the pac commands
  that matter, repo layout, gitignore, the pull request workflow, and git discipline.
