---
name: powerapps-build-playbook
description: >-
  Plan and run a whole Power Apps build end to end: the platform map (what is code versus
  what is clicks), the phase sequence (process understanding, clickable mockup, SharePoint
  first, app skeleton, container loop in source, flows last, hardening), the
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

1. Orient with `references/platform-map.md`: the stack, why SharePoint and not Dataverse,
   and the five bucket map of what is code versus what is manual clicks. Never promise in
   code what belongs to a clicks bucket.
2. Run the phases in `references/build-playbook.md` in order: understand the process,
   clickable mockup, SharePoint first, app skeleton, container by container with a human in
   the loop, flows last, then harden.
3. The human does the clicks. Sites, lists, columns, permissions, connections, flow
   skeletons, the first import, sharing, adding flows in Studio, the Studio publish after a
   ship. Write them exact specs from
   `references/manual-steps.md` and track pending manual work in a STUDIO_TODO.md.
4. Every change is confirmed working in the real app before it is committed. Never commit
   unconfirmed changes.
5. To set up the collaboration itself (instructions template, division of labor, running the
   loop), use `references/working-with-ai.md`.

## Hard rules

- Build the whole app in source, people pickers and attachment forms included, and ship it
  through its app-only solution with the procedure in the `powerapps-source-workflow` skill.
  Never write `SearchItems` into pa.yaml. Picker search is restored after each ship.
- Redact anything shareable. A fictional company name, role titles instead of people names,
  placeholder tenant URLs and GUIDs. Verify with a grep before committing.
- Keep the docs honest. A gotcha earned on a real build gets added to the matching reference
  the same session. When reality contradicts a doc, fix the doc.

## References in this skill

- `references/platform-map.md`: the stack, the five bucket code versus clicks map, and
  the design principles.
- `references/build-playbook.md`: the end to end phase sequence with time expectations.
- `references/manual-steps.md`: every click that can never be code, exact specs, the
  STUDIO_TODO.md artifact, and small edits pasted in Studio.
- `references/working-with-ai.md`: wiring an AI assistant into the build, the custom
  instructions template, the division of labor, and the redaction convention.
