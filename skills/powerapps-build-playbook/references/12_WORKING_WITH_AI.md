# 12: Working with an AI assistant. Turning these docs into a build companion

These docs exist so an AI assistant with them in context can do the code side of a Power Platform build: the YAML, the Power Fx, the flow JSON, the data model, the docs. This page is how to wire that up and how to run the collaboration so it actually works.

---

## Two ways to connect

### Option A: install the skills into your coding agent

The repo ships task specific skills that work in Claude Code, Codex, and Cursor. The Install
section in README.md is the single source of truth: Claude Code installs the repo as a
plugin, Codex and Cursor read the skill folders from `~/.agents/skills/` after one clone and
copy. Once installed, the right skill triggers on its own Power Apps work and the agent can
edit pa.yaml source, run pac commands, manage git, and draft the docs directly. Working
inside this repo itself, AGENTS.md routes the agent to the skills.

### Option B: a chat project with knowledge files

Create a project in your AI tool (a Claude Project or equivalent). Upload these docs to the project knowledge. For a specific app, also upload that app's own knowledgebase (its architecture, data model, step logic, automation, developer rules docs). Paste the custom instructions below into the project's instructions field.

Per app knowledge beats generic knowledge. This repo teaches the method. Each app repo should grow its own numbered knowledgebase describing that app's real lists, real step logic, and real rules, refreshed when the app changes. The assistant is only as current as those files, so re-upload after significant changes.

## The custom instructions template

This is the distilled version of the instructions that ran a production build. Adapt the bracketed parts.

```
ROLE
You are a build companion for [App Name], an internal Power Apps canvas app at
[Company] that [one line purpose]. I am the developer building it. You generate
the technical pieces: Power Fx formulas, SharePoint patches, Power Automate flow
logic, and control configuration. The knowledge files are the source of truth
for architecture, data model, step logic, automation, and developer rules.

BUILD MODE (default)
Provide the FULL, complete, production ready formula. If multiple properties
need updates, give each its own complete block, labeled with the control name
and property. If a new variable is required, state exactly where it is set
(App.OnStart, screen OnVisible, or a specific button OnSelect) and provide the
full Set() line. Never assume I will merge logic by hand. Assume I will paste
exactly what you provide into the Power Apps property editor.

TEACH MODE (only when I ask why)
1. State the rule in one sentence. 2. Show the relevant pattern. 3. Explain the
consequence of violating it. 4. Show correct versus incorrect.

COMMUNICATION RULES
1. Auto correct, do not scold. If I attempt something that violates the
   developer rules, immediately provide the corrected implementation and cite
   the rule in one line.
2. Full replacement standard. Every fix is the entire formula, a direct
   replacement. No fragments, no "add something like this".
3. No ambiguous language. No "you could try". Provide the definitive
   implementation.
4. Choice column safety. SharePoint stores Choice options in the column
   configuration, not in code, so the documented values can drift. Before any
   task that patches, filters, or switches on a Choice column's values, stop
   and ask me to paste the current values from SharePoint settings.
5. Unused column safety. Columns documented as defined but unused must not be
   silently wired up. Say the column is unused and ask whether to wire it.
6. Schema changes. When I add, rename, or remove a SharePoint column mid
   conversation, acknowledge it, ask whether to update the data model doc now,
   and flag any existing code that references it. Remind me that display name
   renames do not change internal names.

DESIGN PHILOSOPHY (non negotiable)
Governance over convenience. Files are truth (gate on file index rows, not
checkboxes). State lives in SharePoint, UI variables are mirrors synced in
OnVisible. Never patch raw values into Choice, Lookup, or Person columns. Every
step moving patch includes the step, the substep reset, and Last_Updated_On.
Cycle scoped queries always filter on the current cycle. Admin visibility is
not admin authority. One writer per column.
```

## The division of labor

The assistant cannot click. Keep the boundary explicit in every plan:

| The AI does | The human does |
|---|---|
| Design the data model, write the column specs | Build the site, lists, columns, permissions (10_MANUAL_STEPS.md) |
| Write and edit pa.yaml source (era 1) | Pack or import, or both if a coding agent runs pac |
| Write exact paste ready Power Fx (era 2) | Paste into Studio, test, confirm |
| Write flow JSON logic | Create flow skeletons, export, import, add flows to the app |
| Write STUDIO_TODO.md specs for Studio only controls | Build the combos and attachment forms in Studio |
| Mirror confirmed changes into the repo, write commits and PRs | Approve what ships, merge (or delegate merging after confirming) |
| Keep the docs true | Report what the screen actually shows |

## Running the loop well

- One container, one flow, or one fix per turn. Real apps get built in hundreds of small confirmed turns, not five big drops.
- Feedback is what you see: the red error text, a screenshot, "the button stays grey". The errors panel message is gold, paste it verbatim.
- Paste first, confirm, then mirror to git. Never commit unconfirmed changes (10_MANUAL_STEPS.md).
- When the assistant asks for the current Choice values or the real column names, that is the process working. Paste from SharePoint settings, do not answer from memory.
- Start each work session by stating where things stand ("we are past the one way door", "the folder flow is wired, notifications are not"). Or better, keep STUDIO_TODO.md current and point at it.

## Redaction convention for everything that leaves the machine

App repos and doc repos get shared. Write them redacted from the first commit:

- The real company name never appears. Use an alias ("ABC Company" or similar) everywhere, including diagrams and sample data.
- People appear as role titles (the COO, the finance lead, a sales rep), never as names.
- Real tenant URLs, environment URLs, list GUIDs, and connection reference names stay out of committed docs. Use `https://<tenant>.sharepoint.com/sites/<Site>` shapes. The exception is functional files that cannot work without real values (flow JSON in a private app repo). Know which repos are private enough for that and keep genuinely secret material out via .gitignore regardless.
- Sample data uses fictional customers (Northwind, Contoso, Acme).
- Keep the original confidential source documents in a gitignored `source_files/` folder.

After writing, verify: grep the files for the real company name and real people names before committing.

## Keep the docs honest (the compounding rule)

When a new gotcha, pattern, or fix earns its keep on a real build, it gets added to the relevant doc in this repo (or the app's knowledgebase) the same day. When something here turns out wrong or stale, fix it. This repo is only valuable while it reflects what actually happens at the keyboard. That maintenance loop, more than any single pattern, is what makes each new app dramatically faster to build than the last.
