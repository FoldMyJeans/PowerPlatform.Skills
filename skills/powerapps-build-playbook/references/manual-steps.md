# Manual steps playbook. Every click that can never be code

An AI assistant (or a remote developer) can write the YAML, the Power Fx, and the flow JSON. Everything on this page is what the human at the keyboard must do in a browser or in Power Apps Studio. Treat it as the standing division of labor, and keep a per app STUDIO_TODO.md that logs which of these are pending and exactly how to do each one.

---

## One time, per environment

| # | Step | Where |
|---|---|---|
| 1 | Create the pac auth profile: `pac auth create --environment https://<org>.crm.dynamics.com` | Terminal, but interactive login |
| 2 | Create connections for SharePoint and Outlook (first use of each connector prompts) | make.powerapps.com |

## Per app, backend first (phase 1 of the build playbook)

| # | Step | Notes |
|---|---|---|
| 1 | Create the SharePoint team site | Name and URL feed the schema doc and every flow |
| 2 | Create each list and every column, exact names and types | Against the written spec. No spaces in names. Order: roles list, main list, then the lists that look up into the main list. Choice values exactly as specced |
| 3 | Create the document library, the top level route or bucket folders, and a Templates library holding the master checklists | Per record subfolders are made later by the flow |
| 4 | Seed the roles list | At least one Admin row plus every approver role, or OnStart reads blanks |
| 5 | Set SharePoint permissions | Lists Contribute or Read per the access model, confidential subfolder locked to its group (the `powerapps-approvals-and-flows` skill) |
| 6 | Confirm the real internal column names back into SCHEMA_AS_BUILT.md | The code is written against these, so this closes phase 1 |

## Per app, canvas app side

| # | Step | Notes |
|---|---|---|
| 1 | Import the first packed .msapp | Apps, Import canvas app, from this device. The "validate by opening in Studio" banner on a YAML packed app is expected |
| 2 | On first open, add the data sources | Add each SharePoint list once. Survives re-imports |
| 3 | Create the app-only solution | Solutions, New solution, then Add existing, App, Canvas app. The app goes in alone, flows get their own solution. Every ship after this is command line and keeps the AppId (the `powerapps-source-workflow` skill) |
| 4 | Run App.OnStart | Tree view, App, three dots, Run OnStart. Do it after every import and every OnStart edit |
| 5 | Check the Formulas and errors panel | Zero red before anything else. This, not a clean pack, is the correctness check |
| 6 | Share the app with users, publish | Share adds users, publish makes the saved version live |
| 7 | After every ship of an app with people pickers, open it for edit and Publish | Step 4 of the shipping procedure. Nothing to paste. The picker search fix runs on the app this publish produces |
| 8 | Grab the app play URL | Apps, Details, Web link. Needed by every notification flow and deep link button. Replace any `<APP_PLAY_URL>` placeholder in button code with it, a placeholder here means dead email links |

## Per app, flow side

| # | Step | Notes |
|---|---|---|
| 1 | Create each flow skeleton | PowerApps V2 trigger, inputs named and ordered, connection wired, one placeholder action. Then export for the code side to fill in (the `powerapps-approvals-and-flows` skill) |
| 2 | Map connection references, first import only | Only when a solution lands in an environment for the first time. Every import after that is code: `pac solution import --path <zip> --async --max-async-wait-time 8` (the `powerapps-source-workflow` skill) |
| 3 | Add each flow to the app | Studio, Power Automate pane, Add flow. A `.Run()` does not resolve without this |
| 4 | Re-add a flow after its inputs change | Remove and re-add in the pane. Clears the "received N, expected M" signature cache |
| 5 | Turn the flows on and test one run each | Check the run history for green |

## The STUDIO_TODO.md artifact

Every app repo keeps one. It is what lets the manual phase happen without the person who wrote the code. Structure that worked:

1. A status line: what is shipped, and whether the repo is pulled up to date with the live app.
2. One numbered section per pending manual item: exactly where to click, the exact names, and any formula blocks to paste, ready for copy paste. Mark items DONE with the date when confirmed, keep the original spec below for reference.
3. A "done in YAML" section listing what already works, so nobody rebuilds it.
4. A "known issues to clear at the end" section (for example the flow signature cache refresh).

## Small edits pasted in Studio

A handful of formula changes is often quickest pasted straight into Studio:

1. The code side (AI or developer) writes the exact property values and formula blocks, stated as "control X, property Y, paste this".
2. The human pastes into Studio, tests in the running app, publishes.
3. Only after the human confirms it works: pull the app into source on a branch, commit, open the PR (the `powerapps-source-workflow` skill). If it is rejected, nothing is committed.

Pull before anyone edits source again, or the next ship overwrites the Studio work. Anything bigger than a handful of formulas (a restyle, a new panel, new pickers) is quicker edited in source and shipped.
