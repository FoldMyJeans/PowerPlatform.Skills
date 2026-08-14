---
name: powerapps-powerfx
description: >-
  Write and fix Power Fx formulas for SharePoint backed canvas apps: Patch, lookups, filters,
  flow calls, IfError, and the 22 non negotiable rules that prevent the classic failures. Use
  whenever the user asks for any canvas app formula, has a Power Fx error, patches a record,
  reads a Choice or Yes/No or Person column, calls a flow with .Run, or hits an untyped Table
  default, an As alias scope issue, or a wrong blank. Trigger on "my Power Fx has an error",
  "write the OnSelect formula", "patch is not saving", "formula returns blank", "how do I
  filter", "call the flow from the app". Assumes SharePoint backed canvas apps on standard
  Microsoft 365 licensing, no Dataverse.
---

# Power Fx rules

This skill owns every Power Fx formula. The 22 rules in
`references/06_POWERFX_RULES.md` are non negotiable physics, each written as wrong versus
right code.

## When to use

Use this whenever a formula is written or debugged. For where state lives and the app shell
(OnStart sections, OnVisible sync, view state) use `powerapps-architecture-and-ui`. For list
and column design use `powerapps-sharepoint-data`. For flow definitions use
`powerapps-approvals-and-flows`. For an unexplained error message check
`powerapps-troubleshooting` first, it is probably listed.

## Workflow

1. Before writing, load `references/06_POWERFX_RULES.md` and find the rules the formula
   touches. Writing to SharePoint: rules 1 to 7. Reading and querying: 8 to 10. Type traps:
   11 to 13. Controls: 14 to 17. Flow calls: 18 to 20. URLs: 21. Verification: 22.
2. Before coding against a Choice column's values, ask the user to paste the current values
   from SharePoint settings. Choice options live in the column configuration and drift.
3. Deliver the complete, paste ready formula labeled with control and property. If a new
   variable is required, state exactly where it is set (App.OnStart, screen OnVisible, or a
   specific OnSelect) with the full Set() line. Never hand the user a fragment to merge.

## Hard rules most often violated

- Never patch raw values into Choice, Lookup, or Person columns (Rule 1).
- Patch, then re-fetch, and stamp `Last_Updated_On` on every step moving patch (Rules 3, 4).
- One writer per column. Check who owns a column before adding a Patch (Rule 6).
- Cycle scoped queries always filter on the current cycle (Rule 8).
- Wrap multi patch saves and flow calls in IfError (Rules 7, 20).

## References in this skill

- `references/06_POWERFX_RULES.md`: all 22 rules with wrong versus right code for each.
