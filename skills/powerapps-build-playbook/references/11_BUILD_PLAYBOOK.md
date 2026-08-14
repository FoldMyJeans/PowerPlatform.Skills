# 11: Build playbook. A new app from zero, end to end

The full method, in the order that worked. It front loads the thinking (process, mockup, data model) because canvas apps are wide and interdependent, and it sequences the build around the one way door. Expect the phases to overlap a little in practice, but never skip one.

---

## Phase 0: understand the process before any technology

1. Collect the source material: the process documents, checklists, presentations. Keep the originals in a `source_files/` folder that is gitignored (they are confidential).
2. Write the knowledgebase: numbered markdown docs distilling the process. One per topic. The set that worked: the full process (scope, steps, roles, decision rules), open questions for the process owner, and solution design notes.
3. Log every ambiguity as a numbered open question aimed at the process owner. Contradictions between documents, unspecified orderings (do approvers decide in sequence or parallel), missing artifacts. Do not resolve them by guessing, park them and design a documented default.

## Phase 0.5: the clickable mockup (validate before building)

Build a single file HTML prototype of the whole app and walk stakeholders through it before touching Power Apps. This is the cheapest place to be wrong. What the mockup carries:

- Every screen of every route, clickable end to end, with a stepper.
- Every field editable, so the review meeting can try values live.
- A demo data toggle: demo mode fills every screen with one coherent fictional story record, clean mode shows everything empty.
- A collapsed "questions for the process owner" box on each screen listing the open questions that affect that screen, each with an answer field. Plus a collapsed free notes box per screen.
- A save button that exports one JSON file of every question, its recorded answer, and all notes, so a review session's feedback feeds straight back into the docs.

The goal stated plainly: the prototype hands an engineer 100 percent of the business logic, and shows exactly what is still unconfirmed. Keep a fidelity map doc listing where the real app must differ from the mockup.

## Phase 1: SharePoint first. No app code until the backend is real.

The app reads the lists on start, so the names must be real before the code can use them.

1. Design the lists on paper using the standard four list shape (04_SHAREPOINT_DATA.md in the `powerapps-sharepoint-data` skill).
2. A human builds the site, the lists, the library, the templates library, seeds the roles list, sets permissions (the exact click list is 10_MANUAL_STEPS.md).
3. Confirm the real internal column names and Choice values back into SCHEMA_AS_BUILT.md. That doc is now the contract. Phase 1 is done when it is filled in.

## Phase 2: app skeleton

Deliver `App.pa.yaml` (theme, view state, OnStart sections per 05_APP_ARCHITECTURE.md in the `powerapps-architecture-and-ui` skill) plus the one screen with the master container, the top bar, and empty child containers. Pack, import, add the data sources once, run OnStart, confirm it opens clean. Nothing works yet. This is the frame.

## Phase 3: build container by container, in a loop with a human

Never deliver the whole app in one drop. One container (or one list) per turn:

1. Write or change one piece in the YAML source.
2. Write one short note: what changed, what to test.
3. The human packs (or pastes), imports, opens, tests that one piece.
4. They report what they see (screenshots are fine). Fix or move on.

The planned order that worked: top bar and stepper first, then the home or menu views, then routing screens, then the main route end to end, then the sibling routes (they reuse the shared panels), then dashboards. Shared panels get built once, at app level, the first time any route needs them.

Two decisions to lock with the human before the first container, because both are expensive to change later:

- The route and step model (how many routes, which steps each has).
- What is shared versus duplicated (documents panel, approval panel, stepper). Default to shared.

## Phase 3.5: sequence the one way door

While still in era 1 (everything packs), land every last thing that can be expressed in YAML: all containers, all formulas, all gating, placeholder labels where the Studio only controls will go, and buttons with interim OnSelects (patch the flag directly) where flows will later be wired. Then, in one Studio session, the human builds the era 2 items from STUDIO_TODO.md: people pickers, the attachment form, flow wiring. From that session on, the workflow is Studio plus mirror (03_SOURCE_WORKFLOW.md in the `powerapps-source-workflow` skill). Never pack again.

## Phase 4: flows last

The app runs first with interim patches, so flows are not on the critical path. Then per flow: skeleton in the designer, export, fill the JSON, import, add to the app, wire the real `.Run()`, test a run (09_FLOWS.md in the `powerapps-approvals-and-flows` skill). Folder creation first (the folder gate depends on it), uploads second, notifications last.

## Phase 5: harden

- Sweep every save button into the IfError pattern, every flow call wrapped, every patch re-fetched (06_POWERFX_RULES.md in the `powerapps-powerfx` skill).
- Walk the permission model as three different test users: a sales rep who is on one deal, an approver, an admin. Check every gate and every gallery scope.
- Test the return loop twice in a row (cycle 1 reject, cycle 2 reject) and confirm no stale approvals leak.
- Test deep links from real emails.
- Lock a record and confirm everything goes read only.
- Update SCHEMA_AS_BUILT.md, STUDIO_TODO.md, and the knowledgebase to match reality. Docs that drift are worse than no docs.

## The standing rules across all phases

- Small pieces, confirmed by a human in the real app, then committed. Nothing unconfirmed lands in git.
- The repo mirrors the live app, never leads it after era 1.
- Every gotcha discovered gets written into these docs (or the app's own knowledgebase) the day it is found. That is the entire reason this playbook exists.

## Time expectations

Calibration from real builds: the mockup and knowledgebase phase is days, not hours, and worth every one (it is where the stakeholders change their minds cheaply). The YAML era of the app build is fast (whole routes per day once the shared panels exist). The Studio era is slower per change but stable. The flows are a day or two each the first time, then an hour each once a solution and connection reference exist to copy from.
