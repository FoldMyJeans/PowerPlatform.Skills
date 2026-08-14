# 07: UI patterns. The proven building blocks with their formulas

Every pattern here shipped in production. Copy the shape, adapt the names, keep the why.

---

## Pattern: clickable stepper (browse without moving)

The top bar shows the steps of the current route. Users must be able to open an already reached step for reference without changing the record's real position. The trick is two variables: the record's real step (in SharePoint) and a local viewed step.

```
// App.OnStart
Set(varViewStep, 0);            // 0 means: show the live step

// the effective step, used in EVERY step container's Visible
If(varViewStep > 0, varViewStep, varDeal.Current_Step)

// the stepper is a horizontal Gallery of buttons (HtmlViewer cannot click)
// tile DisplayMode: lock the future
DisplayMode: =If(ThisItem.n <= varDeal.Current_Step, DisplayMode.Edit, DisplayMode.Disabled)

// tile OnSelect: click the current step to snap back to live
OnSelect: =Set(varViewStep, If(ThisItem.n = varDeal.Current_Step, 0, ThisItem.n))

// any real move (the named Move buttons) changes the field AND resets the view
Patch(Deals, varDeal, { Current_Step: varDeal.Current_Step + 1, Last_Updated_On: Now() });
Set(varDeal, LookUp(Deals, ID = varDeal.ID));
Set(varViewStep, 0)
```

Color tiles by state: current (`ThisItem.n = varDeal.Current_Step`), being viewed (`varViewStep > 0 && ThisItem.n = varViewStep`), done (`ThisItem.n < varDeal.Current_Step`), locked (the rest). Make the stepper data driven: the gallery reads each route's step list from a small inline table variable (`varRoutes`), so one stepper serves every route.

### Variant with real navigation and evidence gates

A stronger variant lets tile clicks actually move the record in the early steps, with rules:

- Free navigation window: both current and target step at most 5. From step 6 on, tile clicks are no-ops with a toast ("Navigation locked once you reach Step 6. Use Back and Next buttons."), because late steps have side effects (creating reviewer rows, notifications, cycle increments) that must not be bypassed.
- Backward clicks always allowed. Forward clicks enforce the cumulative evidence gates (file counts, validation flags), the same checks as the Next buttons, with a specific toast naming what is missing.
- A forward only `Max_Step_Reached` text column records the highest checkpoint reached through the official Next buttons, so gating survives refreshes and rejection cycles.

If you use forward gates, they exist in several places (the Next buttons plus every click handler). Change them together or not at all.

## Pattern: gating a panel on a precondition

When a step needs something done first (create the folder, save the customer), show a "do this first" panel in the same slot as the real panel, mutually exclusive on one flag:

```
// gate panel (con_FolderGate)
Visible: =<on the right steps> && !Coalesce(varDeal.Folder_Created, false)

// real panel (con_Docs)
Visible: =<on the right steps> && Coalesce(varDeal.Folder_Created, false)
```

This reads far better than a greyed out control nobody understands. The gate panel holds the one action that clears it (the Create folder button) and one sentence of why.

## Pattern: shared route aware panel

Control names are global, so a panel used by four routes is built once at app level and made route aware:

```
// visible on the approval step of any route (eff is the effective step)
Visible: =!IsBlank(varDeal) && (
    (varView = "FULL_FLOW" && eff = 3) ||
    (varView = "LIGHT_A"   && eff = 3) ||
    (varView = "LIGHT_B"   && eff = 4) ||
    (varView = "LIGHT_C"   && eff = 3))

// content that differs per route reads from a Switch with a TYPED default
Items: =Switch(varView,
    "FULL_FLOW", Table({ r: "President" }, { r: "COO" }, { r: "CFO" },
                       { r: "VP of Sales" }, { r: "Legal" }),
    "LIGHT_C",   Table({ r: "COO" }, { r: "CFO" }, { r: "VP of Sales" }),
    Table({ r: "" }))        // typed default, see 06_POWERFX_RULES.md in the `powerapps-powerfx` skill Rule 11
```

The shared panels that earned their keep: documents (upload plus link register plus gallery), approvals (per approver rows plus actions), the folder gate, a templates shortcut button. Hide the documents panel on the approval step (the approval panel takes the slot) and on the final step (no uploads after approval).

## Pattern: concurrency safe step moves

Many people sit in one record at once. Browsing never writes (the stepper pattern above). Moving re-reads before writing:

```
// Move button OnSelect (after the confirm)
With({ live: LookUp(Deals, ID = varDeal.ID) },
    If(
        live.Current_Step <> varDeal.Current_Step,
        // someone else already moved it: stop and refresh instead of overwriting
        Set(varDeal, live);
        Notify("This deal was just moved by someone else. The view has been refreshed.",
               NotificationType.Warning),
        // safe: perform the move
        Patch(Deals, live, { Current_Step: live.Current_Step + 1, Last_Updated_On: Now() });
        Set(varDeal, LookUp(Deals, ID = varDeal.ID));
        Set(varViewStep, 0)
    )
)
```

Move buttons are named for the destination ("Move to: Financial analysis") and show a short confirm, so changing the shared record is always a deliberate act.

## Pattern: send notification debounce plus auto grey

Save and Send are two buttons. The flow behind Send reads rows the Save button just wrote, so SharePoint must commit first. And after a successful send, the button must grey out so nobody double emails executives. Three parts:

```
// App.OnStart
Set(varSendNotification_Ready, true);
Set(varSendNotification_TimerStart, false);

// hidden timer, last child of the master container
// tmr_SendNotification_Debounce: Duration 1500, Start: =varSendNotification_TimerStart
OnTimerEnd: =Refresh(Approvals); Set(varSendNotification_Ready, true)

// BOTH Save and Send OnSelects start with the gate down, and end with the timer pulse
Set(varSendNotification_Ready, false);
/* ... patches or flow .Run ... */
Set(varSendNotification_TimerStart, false);
Set(varSendNotification_TimerStart, true);

// Send button DisplayMode carries all the gates
DisplayMode: =If(
    Coalesce(varSendNotification_Ready, true)                       // debounce
    && CountRows(Filter(Approvals,
        Deal.Id = varDeal.ID && Step_Number.Value = "7" &&
        Review_Cycle = varDeal.Review_Cycle &&
        Coalesce(Notification_Sent, false) <> true)) > 0        // rows still unsent
    && !Coalesce(varStep5A_FormDirty, false),                      // unsaved edits block send
    DisplayMode.Edit, DisplayMode.Disabled)
```

How the auto grey works: the flow (not the app) patches `Notification_Sent: true` per row it emails. The timer's `Refresh` pulls those flags, the unsent count hits zero, the button greys permanently for the cycle. Re-enabling is data driven too: change the meeting date or the assigned person and the count formula (which compares the stored notified date against the picker) goes positive again. A dirty flag (`varStep5A_FormDirty`, set by the pickers' OnChange, cleared by Save) blocks sending unsaved edits.

The failure path matters: the IfError catch on Save must reset `varSendNotification_Ready` to true, or a failed save leaves the Send button dead forever (06_POWERFX_RULES.md in the `powerapps-powerfx` skill Rule 7).

## Pattern: per row approval gallery with authority

One gallery over the approval rows of the current record and cycle. Each row carries its own Approve and Return buttons plus a comment box:

```
// row Approve button DisplayMode
DisplayMode: =If(
    Coalesce(varDeal.Is_Locked, false)
    || !(Lower(Coalesce(ThisItem.Assigned_To.Email, "")) = varUserEmailLower
         || varIsSuperApprover)
    || ThisItem.Decision.Value = "Approved",
    DisplayMode.Disabled, DisplayMode.Edit)

// row Approve OnSelect
Patch(Approvals, ThisItem, { Decision: { Value: "Approved" },
    Comment: txt_RowComment.Text, Decided_Date: Now() });
// then recompute the deal level status from the rows and re-fetch varDeal
```

Notes. A row control (`txt_RowComment`) is referenced by its sibling button inside the same gallery template, that works. `varIsSuperApprover` is computed once in OnStart from the roles list (President or COO) and grants any-row authority plus an "Approve all remaining" button. Friction matches the stakes: Approve is one click with an Undo appearing after, Return asks for a reason and one plain confirm sentence. Full approval mechanics in 08_APPROVALS_PERMISSIONS.md in the `powerapps-approvals-and-flows` skill.

## Pattern: actionable dashboards

Two dashboards proved the right split: a records dashboard (every record, search, open) and a workload dashboard (what needs action). The workload one is the pattern worth copying:

- A row of KPI tiles counting by status (`CountRows(Filter(Deals, Status.Value = "Waiting for approval"))`), plus one personal tile: "Waiting on you" counts pending approval rows assigned to the current user (or all pending rows for a super approver).
- Tiles are clickable filters. Clicking a tile sets a filter variable and the gallery below filters to match. Clicking again clears it.
- The gallery flags rows needing the current user (a star and a warning color) via the per row email check.
- An empty state label ("Nothing waiting on you") when the filtered set is empty.
- A Refresh button, because SharePoint side adds and deletes do not surface on their own:

```
// btn_Refresh OnSelect
Refresh(Deals);
If(!IsBlank(varDeal), Set(varDeal, LookUp(Deals, ID = varDeal.ID)))
```

The re-lookup of the open record stops an open detail view from going stale after the refresh. For `Refresh()` to surface new rows, the gallery `Items` must bind to the data source itself (with inline filters), not to a collection snapshot.

## Pattern: guided intake plus directory

Two doors into the same routes. A guided questionnaire (two or three plain language questions) that ends at a verdict screen naming the route, the approvers, and what to prepare, with a Start button. And a directory screen listing every route with full names for people who already know. Both set the same `varView`. Dead ends (exempt outcomes) are information screens with Back and Home, they save no row.

## Pattern: friction matched confirms

- Low risk actions (approve): one click, then an Undo button while the round is open.
- Record moving actions (Move, Return): one short confirm sentence stating exactly what changes.
- Destructive or final actions (Close dead deal, Lock): a firmer confirm plus a required reason, restricted to senior roles.

## Pattern: demo data toggle (for mockups and demos)

A global switch: demo mode fills every screen with one coherent fictional record so a stakeholder can follow a single story end to end, clean mode shows everything empty and interactive. Cheap to build, transforms review meetings. Pairs with the mockup method in 11_BUILD_PLAYBOOK.md in the `powerapps-build-playbook` skill.
