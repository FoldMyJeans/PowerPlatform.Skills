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
| 1 | Import the packed .msapp (era 1) | Apps, Import canvas app, from this device. The "validate by opening in Studio" banner on a YAML packed app is expected |
| 2 | On first open, add the data sources | Add each SharePoint list once. Survives re-imports |
| 3 | Run App.OnStart | Tree view, App, three dots, Run OnStart. Do it after every import and every OnStart edit |
| 4 | Check the Formulas and errors panel | Zero red before anything else. This, not a clean pack, is the correctness check |
| 5 | Share the app with users, publish | Share adds users, publish makes the saved version live |
| 6 | Grab the app play URL | Apps, Details, Web link. Needed by every notification flow and deep link button. Replace any `<APP_PLAY_URL>` placeholder in button code with it, a placeholder here means dead email links |

## Per app, flow side

| # | Step | Notes |
|---|---|---|
| 1 | Create each flow skeleton | PowerApps V2 trigger, inputs named and ordered, connection wired, one placeholder action. Then export for the code side to fill in (the `powerapps-approvals-and-flows` skill) |
| 2 | Map connection references, first import only | Only when a solution lands in an environment for the first time. Every import after that is code: `pac solution import --path <zip> --async --max-async-wait-time 8` (the `powerapps-source-workflow` skill) |
| 3 | Add each flow to the app | Studio, Power Automate pane, Add flow. A `.Run()` does not resolve without this |
| 4 | Re-add a flow after its inputs change | Remove and re-add in the pane. Clears the "received N, expected M" signature cache |
| 5 | Turn the flows on and test one run each | Check the run history for green |

## Studio only controls (the one way door items)

These cannot be packed from YAML, ever (the `powerapps-source-workflow` skill). Build them in Studio as the last step of the initial build. The YAML should already hold placeholders marking where they go. Once these exist, never pack again.

### People picker combo boxes

Insert, Input, Combo box. Per picker:

- Name it exactly what the YAML expects (for example `cmb_S1_SalesOwner`), because the Save button references it by name.
- Items: `Choices(<List>.<PersonColumn>)` for the directory behind that column.
- Display field and Search field: `DisplayName`. Allow multiple selection: Off.
- DefaultSelectedItems: `If(IsBlank(varDeal.Sales_Owner), [], Table(varDeal.Sales_Owner))` (swap the field per picker). For pickers pre-filling from an approvals row, the LookUp must include the cycle filter.
- Then extend the Save button's Patch with the person writes: `Sales_Owner: cmb_S1_SalesOwner.Selected, ...`

Build one, copy it, change the field. Three pickers is ten minutes.

### The attachment upload form

The native multi file picker is a form stack: `Form` (New mode, bound to the file index list) containing a `TypedDataCard` (variant ClassicAttachmentsEdit) containing an `Attachments` control. You cannot insert the attachment control alone. The reliable way:

1. Copy a working upload form from an existing app if you have one, or create a form bound to the list and keep only the attachments card.
2. Name the three levels (`frm_Docs_Upload`, `dc_Docs_Attachments`, `att_Docs_Files`).
3. Position it where the YAML placeholder sits, then delete the placeholder label.
4. Wire the upload button: loop `att_Docs_Files.Attachments As f` into the upload flow (the `powerapps-approvals-and-flows` skill), then `Refresh(<index list>); ResetForm(frm_Docs_Upload); Reset(<link inputs>)`.

### Adding flows to the app

Also Studio only (the Power Automate pane), covered above. Wiring the real `.Run()` calls into buttons that shipped with placeholder OnSelects is part of this batch.

## The STUDIO_TODO.md artifact

Every app repo keeps one. It is what lets the manual phase happen without the person who wrote the code, and it stops anyone from attempting a pack that will now fail. Structure that worked:

1. A banner stating whether the app is past the one way door, and what that means for the workflow.
2. One numbered section per pending manual item: where it goes (container, coordinates), exact control names, every property value, and the exact formula blocks to paste, ready for copy paste. Mark items DONE with the date when confirmed, keep the original spec below for reference.
3. A "done in YAML" section listing what already works, so nobody rebuilds it.
4. A "known issues to clear at the end" section (for example the flow signature cache refresh).

## The paste driven change loop (era 2 steady state)

After the one way door, every change follows this ritual:

1. The code side (AI or developer) writes the exact property values and formula blocks, stated as "control X, property Y, paste this".
2. The human pastes into Studio, saves, tests in the running app.
3. Only after the human confirms it works: mirror the same change into the repo YAML, commit on a branch, open the PR. If it is rejected, nothing is committed.
4. Periodically run the export and unpack on a branch and open a PR to true up the whole repo from the cloud (the `powerapps-source-workflow` skill).

The order is the point. Paste first, confirm, then mirror. The repo only ever contains confirmed reality.
