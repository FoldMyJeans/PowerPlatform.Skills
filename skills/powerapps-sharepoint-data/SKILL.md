---
name: powerapps-sharepoint-data
description: >-
  Design SharePoint lists as the database for a canvas app: the standard four list shape
  (records, file index, roles, approvals), naming rules, column types and how Power Fx reads
  them, delegation limits, and the SCHEMA_AS_BUILT contract doc. Use whenever the user is
  designing or changing lists or columns for an app, choosing a column type, dealing with a
  Choice column, hitting a delegation warning, or documenting the real schema. Trigger on
  "design my SharePoint lists", "what columns do I need", "add a column", "choice column
  values", "lookup or text column", "delegation warning", "the schema doc". Assumes
  SharePoint backed canvas apps on standard Microsoft 365 licensing, no Dataverse.
---

# SharePoint data design

This skill owns the data layer: list shapes, columns, naming, and the schema contract
between SharePoint and the app.

## When to use

Use this when shaping or changing lists and columns. For the formulas that read and write
them use `powerapps-powerfx`. For who creates the lists (the human clicks, the AI writes
exact specs) use `powerapps-build-playbook`. For approval and permission data shapes use
`powerapps-approvals-and-flows`.

## Workflow

1. Start from the standard four list shape in `references/04_SHAREPOINT_DATA.md`: the main
   record list, the file index list, the people and roles list, and the approvals list.
2. Follow the naming rules exactly. They prevent whole classes of bugs.
3. Pick column types with the Power Fx behavior table in the reference. What SharePoint
   calls a column and what Power Fx reads back are not the same thing.
4. The human builds the lists in the browser. Write them an exact spec: list name, column
   internal name, type, and choice values in order.
5. After the human builds, confirm real internal column names into SCHEMA_AS_BUILT.md.
   Display name renames never change internal names.

## Hard rules

- Choice columns drift. The documented values can differ from the live column. Before any
  code that patches, filters, or switches on a Choice column, ask the user to paste the
  current values from SharePoint settings.
- Files are truth. Evidence gates read the file index list, not checkboxes.
- Columns documented as defined but unused are not silently wired up. Say the column is
  unused and ask whether to wire it.

## References in this skill

- `references/04_SHAREPOINT_DATA.md`: the four list shape, naming rules, column types in
  Power Fx, each list in detail, SCHEMA_AS_BUILT.md, delegation reality, and build specs.
