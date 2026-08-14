---
name: powerapps-approvals-and-flows
description: >-
  Build the approval engine, the permission model, and the Power Automate flows behind a
  canvas app: approval rows and cycles and returns, assigning approvers, the two layer access
  model (SharePoint permissions as real security, app gates as UX), per record permissions,
  record locking, flow JSON anatomy, and the four proven flow shapes (create folders, upload
  a file, notify people, scheduled sweep). Use whenever the user adds or debugs an approval
  step, sets permissions, locks records, writes or edits a cloud flow, or wires a flow to the
  app. Trigger on "add an approval", "approvers", "return the record", "permissions", "lock
  the record", "write the flow", "notification flow", "folder flow", "flow JSON". Assumes
  SharePoint backed canvas apps on standard Microsoft 365 licensing, no Dataverse.
---

# Approvals, permissions, and flows

This skill owns the governance machinery: row by row approvals with full cycle history, the
two layer access model, and the Power Automate flows.

## When to use

Use this for approval logic, access control, and flow definitions. For the approval gallery
UI use `powerapps-architecture-and-ui`. For the .Run call formulas use `powerapps-powerfx`.
For creating flow skeletons and importing solutions (human clicks) use
`powerapps-build-playbook`.

## Workflow

1. Approvals follow the engine in `references/08_APPROVALS_PERMISSIONS.md`: the data shape,
   assigning, deciding, the return loop and cycles, and notifying.
2. Permissions are two layers. Layer 1 is SharePoint permissions, the real security. Layer 2
   is app gates, UX only. Never present a hidden button as security.
3. New flows use the skeleton first method in `references/09_FLOWS.md`: the human creates a
   skeleton in the maker portal, exports it, and the JSON is then authored in the repo. Start
   every flow from one of the four proven shapes, do not invent a fifth.
4. Changing a flow's inputs means every app using it must remove and re-add it in the Power
   Automate pane. Plan input changes, do not iterate them.

## Hard rules

- One writer per column. Flow written columns are read by the app, never written by it.
  Before adding any Patch or flow action, check who owns the column.
- Cycle scoped queries always filter on the current cycle.
- Admin visibility is not admin authority. Admins see everything and may do only what their
  role allows.
- Notifications deduplicate and debounce. Follow the suppression contract shared between
  flow and app.

## References in this skill

- `references/08_APPROVALS_PERMISSIONS.md`: the approval engine end to end, and the two
  layer access model including per record permissions, the drop box flow, locking, and
  debugging permissions.
- `references/09_FLOWS.md`: trigger and action anatomy, the four proven flow shapes, the
  skeleton first method, solution registration, app wiring, and the activation time traps.
