---
name: powerapps-architecture-and-ui
description: >-
  Structure a canvas app and build its UI: the single screen shell, the container tree, view
  state, App.OnStart sections, OnVisible data sync, theme, naming conventions, and the proven
  UI patterns (clickable stepper, evidence gates, shared route aware panels, concurrency safe
  step moves, notification debounce, approval galleries, dashboards, guided intake). Use
  whenever the user adds a screen or panel or container, structures OnStart or OnVisible,
  names controls and variables, or builds a stepper, gate, dashboard, or gallery. Trigger on
  "add a screen", "add a panel", "app structure", "OnStart", "stepper", "dashboard in the
  app", "gallery", "navigation in the app". Assumes SharePoint backed canvas apps on standard
  Microsoft 365 licensing, no Dataverse.
---

# App architecture and UI patterns

This skill owns the app shell and the on screen building blocks: one screen, containers as
views, and the pattern library with its formulas.

## When to use

Use this when structuring the app or building UI. For the raw formula rules use
`powerapps-powerfx`. For the approval engine behind an approval gallery use
`powerapps-approvals-and-flows`. For planning which containers to build in what order use
`powerapps-build-playbook`.

## Workflow

1. The shell is one screen with containers as views, driven by a view state variable. Start
   from `references/05_APP_ARCHITECTURE.md` for the container tree, App.OnStart numbered
   sections, deep links, OnVisible sync, theme, and naming conventions.
2. For any interactive element, start from a proven pattern in
   `references/07_UI_PATTERNS.md`, do not invent one. Each pattern ships with its formulas.
3. Deliver complete formulas labeled with control and property, and state where every new
   variable is set.

## Hard rules

- State lives in SharePoint. UI variables are mirrors rehydrated in OnVisible. Never treat a
  variable as the source of truth for shared state.
- Visibility is not authority. A hidden button is UX. Real access control is the two layer
  model in `powerapps-approvals-and-flows`.
- Follow the naming conventions in the architecture reference exactly. Consistent names are
  what make the mirror loop reviewable.

## References in this skill

- `references/05_APP_ARCHITECTURE.md`: why one screen, the container tree, view state,
  App.OnStart sections, deep links, OnVisible as the data sync point, theme, naming, and on
  screen copy rules.
- `references/07_UI_PATTERNS.md`: the pattern library with formulas, stepper, gates, shared
  panels, concurrency safe moves, debounce and auto grey, approval gallery, dashboards,
  guided intake, friction matched confirms, and the demo data toggle.
