# AGENTS.md

Operating rules for this repo, for any coding agent (Claude Code, Codex, Cursor) and any
human editing it. This file is committed on purpose, because the repo is the instructions.

## What this repo is

A playbook for building Power Apps canvas apps on SharePoint and Power Automate, distilled
from production builds and packaged as seven task specific agent skills under `skills/`.
Each skill owns one slice of the work and carries its playbook docs in its `references/`
folder. README.md has the skill table and the doc map.

When working on Power Apps tasks from inside this repo, read the matching skill's SKILL.md
first. It is the operating contract for that slice: the workflow, the hard rules, and the
pointers into its references.

## How the skills are structured

- One folder per skill under `skills/`, each with a `SKILL.md` and a `references/` folder
  holding the numbered playbook docs it owns.
- `SKILL.md` frontmatter has two keys, `name` (matching the folder name) and `description`.
  The description is the trigger, so make it pushy and packed with trigger phrases. Keep it
  under 1024 characters.
- Keep `SKILL.md` short, roughly under 150 lines. The depth lives in the numbered docs.
- Every skill folder is self contained. Never reference a path outside the skill folder.
  Point at another skill by name ("see the `powerapps-powerfx` skill"), never by path.

## Writing style (every doc in this repo)

Plain and direct, no em dashes, no en dashes, no semicolons in prose (code blocks are
exempt, Power Fx needs semicolons), short sentences.

## Redaction (everything here is public)

No real company name, use an alias like "ABC Company". People appear as role titles, never
names. Placeholder tenant URLs and GUIDs only. Sample data uses fictional customers. Verify
with a grep before committing.

## Keep the docs honest

A new gotcha earned on a real build gets added to the matching reference doc the same
session. When reality contradicts a doc, fix the doc. The playbook is only worth what it
reflects.

## Changes via pull request

Make each change on a branch and open a pull request. Do not commit straight to main. A
brand new skill folder needs no manifest change, `.claude-plugin/plugin.json` already
exposes every folder under `skills/`. Bump the `version` in plugin.json so installed copies
pick the change up on the next `/plugin update`.

## Verify before committing

- No em or en dashes and no prose semicolons in changed files.
- Each `SKILL.md` frontmatter `name` matches its folder name, description under 1024 chars.
- No path references leave a skill folder.
- No real company, people, hosts, or secrets slipped in.
