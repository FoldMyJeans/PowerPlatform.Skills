---
name: powerapps-troubleshooting
description: >-
  Fix errors in Power Apps canvas builds: pac and pack failures (PA2108 and friends), Power
  Fx author time and run time errors, state and data oddities, Studio and environment
  problems, and flow wiring errors like "received 9, expected 7-8". Use whenever the user
  pastes any error message or describes broken behavior in a canvas app, pac command, or
  connected flow, before reasoning from first principles, because the error is probably
  already listed with its cause and fix. Trigger on "I get this error", "pack fails",
  "PA2108", "the button stays grey", "the formula shows red", "flow call fails", "it worked
  yesterday". Assumes SharePoint backed canvas apps on standard Microsoft 365 licensing, no
  Dataverse.
---

# Troubleshooting

This skill is the error index: everything that actually broke on real builds, as error to
cause to fix.

## When to use

Any error message or broken behavior lands here first. If the error is listed, apply the
fix. If it is not, the reference ends with how to isolate an unlisted problem, and the fix
then routes to the owning skill: formulas to `powerapps-powerfx`, pack and source issues to
`powerapps-source-workflow`, data shape issues to `powerapps-sharepoint-data`, flow issues
to `powerapps-approvals-and-flows`.

## Workflow

1. Get the exact error text. The errors panel message pasted verbatim is gold. "It does not
   work" is not debuggable.
2. Look it up in `references/13_TROUBLESHOOTING.md`, organized by where it appears: build
   and toolchain, Power Fx at author time, Power Fx at run time, state and data, Studio and
   environment.
3. Apply the listed fix completely. Deliver the full corrected formula or command, not a
   fragment.
4. If the root cause was a missing rule, add the gotcha to the owning skill's reference the
   same session. The index is only valuable while it reflects reality.

## References in this skill

- `references/13_TROUBLESHOOTING.md`: the full error to cause to fix index, plus the
  isolation method for anything not yet listed.
