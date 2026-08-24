# AGENTS.md

Operating rules for this repo, for any coding agent (Claude Code, Codex, Cursor) and any
human editing it. This file is committed on purpose, because the repo is the instructions.

## What this repo is

A playbook for building Power Apps canvas apps on SharePoint and Power Automate, distilled
from production builds and packaged as task specific agent skills under `skills/`. Each skill
owns one slice of the work and carries its reference docs in its `references/` folder.
README.md has the skill table.

When working on Power Apps tasks from inside this repo, read the matching skill's SKILL.md
first. It is the operating contract for that slice: the workflow, the hard rules, and the
pointers into its references.

## How the skills are structured

- One folder per skill under `skills/`, each with a `SKILL.md` and a `references/` folder.
- Reference filenames describe their content (`powerfx-rules.md`, `sharepoint-list-design.md`).
  No numeric prefixes. A number carries no signal about what is inside the file, and the
  reading order it implies stopped being real once the playbook was split into skills.
- `SKILL.md` frontmatter has two keys, `name` (matching the folder name) and `description`.
  The description is the trigger, so make it pushy and packed with trigger phrases. Keep it
  under 1024 characters.
- Keep `SKILL.md` short, roughly under 150 lines. The depth lives in the references.
- Every skill folder is self contained. Never reference a path outside the skill folder.
  Point at another skill by name ("see the `powerapps-powerfx` skill"), never by path.
- Every reference file must be named in its own SKILL.md, or an agent will never load it.

## One name per thing

Every formula in this repo is written against the example schema in the
`powerapps-sharepoint-data` skill. An agent reads a list design from one skill and copies a
formula from another, so a column called `Decided_On` in one place and `Decided_Date` in
another produces code that looks correct and binds to nothing. When you add or rename a
column, grep the whole repo for the old name in the same session.

## Writing rules (apply to every file here)

These govern files in this repo. They are not style advice for your own project's docs, and
nothing here should be applied to a user's app, code, or writing unless they ask for it.

- Plain engineer voice. Short direct sentences. Explain the why, not marketing filler.
- Never use an em dash or an en dash. Use commas, periods, or parentheses.
- Never use a semicolon outside code. Split into two sentences. Power Fx and PowerShell both
  use semicolons, so fenced blocks and inline code spans are exempt and the check knows it.
- Never state a count of things this repo contains. Not the number of skills, not the number
  of references, not "the 22 rules". Every such number is a promise to come back and edit it,
  the edit gets missed, and the number then quietly lies. Say "the skills" and "the rules".
- Show the evidence, do not announce it. Write the symptom and the fix, not "this is a
  critical gotcha". If a thing earned its place on a real build, the detail proves it.
- The Power Fx rules are numbered, and other skills cite them by number. Append a new rule at
  the end of its section and give it the next free number overall. Never renumber, because
  every citation elsewhere silently starts pointing at the wrong rule.

## Redaction (everything here is public)

- No real company name. The examples use a fictional deal review process, keep it that way.
- People appear as role titles (the COO, the finance lead, a sales rep), never as names.
- Placeholder tenant URLs, environment URLs, and GUIDs only. `https://<tenant>.sharepoint.com/sites/<Site>`.
- Sample data uses fictional customers.
- No secrets, connection strings, or real email addresses, ever.

`tools\check.ps1` enforces the mechanical part of this. For terms specific to your own
environment, put one regex per line in `tools\banned.local.txt`. Git ignores that file, so
your terms never reach the repo, and the check picks them up automatically.

## Keep the docs honest

A new gotcha earned on a real build gets added to the matching reference the same session.
When reality contradicts a doc, fix the doc. The playbook is only worth what it reflects.

## Changes via pull request

Make each change on a branch and open a pull request. Do not commit straight to main. A brand
new skill folder needs no manifest change, `.claude-plugin/plugin.json` already exposes every
folder under `skills/`. Bump the `version` in plugin.json so installed copies pick the change
up on the next `/plugin update`.

## Verify before committing

```
pwsh -File tools\check.ps1
```

Exit code 0 means clean. It checks the writing rules, the frontmatter, the size caps, skill
self containment, that every reference resolves and is named in its SKILL.md, that every
skill is listed in README.md, that every JSON parses, and redaction.

What it cannot check, so read for it yourself: whether a formula still matches the example
schema, and whether a claim about the platform is still true.
