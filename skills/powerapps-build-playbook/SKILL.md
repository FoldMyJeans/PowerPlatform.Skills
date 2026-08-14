---
name: powerapps-build-playbook
description: >-
  Plan and run a whole Power Apps build end to end: the platform map (what is code versus
  what is clicks), the phase sequence (process understanding, clickable mockup, SharePoint
  first, app skeleton, container loop, one way door sequencing, flows last, hardening), the
  manual steps playbook with exact click specs and STUDIO_TODO.md, and how to wire an AI
  assistant into the build. Use whenever the user starts a new app, asks what to build first
  or what to click, plans phases, needs specs for manual SharePoint or Studio or maker portal
  work, or sets up the AI collaboration. Trigger on "build a new power app", "plan the app",
  "where do I start", "what do I click", "manual steps", "STUDIO_TODO", "set up the
  collaboration". Assumes SharePoint backed canvas apps on standard Microsoft 365 licensing,
  no Dataverse.
---

# Build playbook

This skill owns the method: the full sequence for a new app, the boundary between code and
clicks, and the collaboration contract between the AI and the human.

## When to use

Use this when starting an app, planning phases, or specifying manual work. The other skills
own their layers: `powerapps-sharepoint-data` for list design, `powerapps-source-workflow`
for pa.yaml and packing, `powerapps-architecture-and-ui` for the shell and patterns,
`powerapps-approvals-and-flows` for governance and flows, `powerapps-powerfx` for formulas,
`powerapps-troubleshooting` for errors.

## Workflow

1. Orient with `references/01_PLATFORM_MAP.md`: the stack, why SharePoint and not Dataverse,
   and the five bucket map of what is code versus what is manual clicks. Never promise in
   code what belongs to a clicks bucket.
2. Run the phases in `references/11_BUILD_PLAYBOOK.md` in order: understand the process,
   clickable mockup, SharePoint first, app skeleton, container by container with a human in
   the loop, sequence the one way door, flows last, then harden.
3. The human does the clicks. Sites, lists, columns, permissions, connections, flow
   skeletons, imports, sharing, Studio only controls. Write them exact specs from
   `references/10_MANUAL_STEPS.md` and track pending manual work in a STUDIO_TODO.md.
4. Code goes to the human first, gets confirmed working, and only then is mirrored into the
   repo and committed. Never commit unconfirmed changes.
5. To set up the collaboration itself (instructions template, division of labor, running the
   loop), use `references/12_WORKING_WITH_AI.md`.

## Hard rules

- Sequence the one way door deliberately. Land everything expressible in YAML while still in
  era 1, then build the Studio only items in one session and never pack again.
- Redact anything shareable. Alias the company name, role titles instead of people names,
  placeholder tenant URLs and GUIDs. Verify with a grep before committing.
- Keep the docs honest. A gotcha earned on a real build gets added to the matching reference
  the same session. When reality contradicts a doc, fix the doc.

## References in this skill

- `references/01_PLATFORM_MAP.md`: the stack, the five bucket code versus clicks map, and
  the eight design principles.
- `references/11_BUILD_PLAYBOOK.md`: the end to end phase sequence with time expectations.
- `references/10_MANUAL_STEPS.md`: every click that can never be code, exact specs, the
  STUDIO_TODO.md artifact, and the paste driven change loop.
- `references/12_WORKING_WITH_AI.md`: wiring an AI assistant into the build, the custom
  instructions template, the division of labor, and the redaction convention.
