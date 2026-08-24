# Approvals and permissions. The engine and the two layer access model

The approval engine and the access model are where governance actually lives. One proven design, with calibration options noted.

---

## The approval engine

### The data shape

One row per approver, per record, per review cycle, in the approvals list (the `powerapps-sharepoint-data` skill). The record itself carries a cycle counter (`Review_Cycle`, starts at 1) and an overall status. That is the whole engine. Everything else is queries over it.

### Assigning approvers

Approvers come from the roles list, assigned by an explicit button, not as a side effect of a step move:

```
// btn_Assign OnSelect (route aware, typed default per the `powerapps-powerfx` skill Rule 11)
ForAll(
    Switch(varView,
        "FULL_FLOW", Table({ r: "President" }, { r: "COO" }, { r: "CFO" },
                           { r: "VP of Sales" }, { r: "Legal" }),
        "LIGHT_C",   Table({ r: "COO" }, { r: "CFO" }, { r: "VP of Sales" }),
        Table({ r: "" })
    ) As role,
    Patch(Approvals, Defaults(Approvals), {
        Deal: { Id: varDeal.ID, Value: varDeal.Deal_Reference },
        Approver_Role: { Value: role.r },
        Assigned_To: LookUp(Role_Config, Role_Name.Value = role.r).Assigned_To,
        Decision: { Value: "Pending" },
        Assigned_On: Now(),
        Step_Number: { Value: "7" },
        Review_Cycle: varDeal.Review_Cycle,
        Notification_Sent: false
    })
)
```

`Step_Number` and `Review_Cycle` are both written here and never left blank. Every query over these rows filters on both, so a row missing either is invisible to the gates that are supposed to count it, and nothing errors. The Send button simply stays grey forever.

Why a button and not the step transition: this was learned as a hard rule in production. The step 6 to 7 Next button only patches the record. The Save Approvers button on step 7 creates the review rows. Keeping row creation out of transitions means a transition can never half fail into duplicate reviewer rows, and approver assignment can be redone without moving the record.

Conditional approvers are data rules: on the lightweight routes the CFO row is added automatically when a concession exists (`Margin_Given_Up > 0`). Optional approvers (a PMO director) are simply rows that may or may not exist, and every "all approved" check adapts to whichever rows were assigned.

### Deciding

Each approver acts on their own row (the per row gallery in the `powerapps-architecture-and-ui` skill). Two decision actions only, Approve and Return (or Reject). The overall outcome flavor (approved, approved with conditions, approved as margin exception) is set once on the record by whoever finalizes, not per approver.

Parallel by default: all assigned approvers decide in any order, the record is approved when no non approved rows remain in the current cycle:

```
Set(varStep7_AllApproved,
    CountRows(Filter(Approvals,
        Deal.Id = varDeal.ID && Step_Number.Value = "7" &&
        Review_Cycle = varDeal.Review_Cycle &&
        Decision.Value <> "Approved")) = 0);
```

Sequential gates where needed: a governance variant lets directors approve in parallel but enables the executive's Approve button only after all assigned directors approved (compare approved director count against assigned director count, so the gate adapts when an optional director was skipped).

### The return loop and cycles

A return is the record moving backward with history kept:

1. The first Return bounces the record. Do not wait for the other approvers.
2. Remaining Pending rows of the cycle are auto closed (decision Rejected, with an auto comment like "Auto-closed due to a rejection in this cycle" so status surfacing can filter them out).
3. The cycle counter on the record increments by one.
4. The record's step moves back to the fix point (intake or drafting), with the return reason stored on the record.
5. Resubmission assigns fresh approver rows under the new cycle number.

Because every query filters on the current cycle, the new round starts clean while the full history of prior cycles stays for audit. A manual "reset cycle" button (senior roles only) covers the case where approvers were assigned wrongly before anyone decided.

Two engineered details that look small and are not. Undo: after approving, an Undo button shows while the round is open, it flips the row back to Pending and clears `Decided_On` back to blank. Close: distinct from Return, a senior only action that permanently closes a dead record as cancelled with a reason. Returns mean fix and resubmit, Close means dead.

### Notifying approvers

Approvers do not poll the app. A flow emails each pending approver of the current cycle with the record summary and two deep links (the app with `dealId`, the folder). The recipients come from the pending rows:

```
Set(varApRecipients,
    Concat(
        Distinct(
            Filter(Approvals,
                Deal.Id = varDeal.ID &&
                Review_Cycle = varDeal.Review_Cycle &&
                Decision.Value = "Pending"),
            Lower(Coalesce(Assigned_To.Email, ""))
        ) As p, p.Value, ";"));
```

`Distinct` matters: one person holding two roles gets one email. The debounce and auto grey pattern (the `powerapps-architecture-and-ui` skill) wraps the Send button. The upgrade path when executives will not open any app: Microsoft Approvals cards in Teams, sent per approver by the flow, with the decision written back to the row. Design for it from the start by keeping one row per approver.

## The two layer access model

### Layer 1: SharePoint permissions. The real security.

List and folder permissions decide what a person can actually read or change. If the app shows a button but the user lacks Contribute on the list, the Patch fails with a permission error. The baseline grid:

| Asset | Typical grant |
|---|---|
| Main record list | Contribute for everyone who works records |
| File index list | Contribute (flows write here as the invoker) |
| Approvals list | Contribute for anyone who can be assigned a review |
| Roles list | Read for everyone, Contribute for admins only |
| Document library | Read on the library, Contribute on folders for uploaders |
| Confidential subfolder (financial analysis) | Locked to finance, the executive approvers, admins |

The most common "bug" in production is not a bug: a user gets "you don't have permission to do this" on Save, and the fix is SharePoint permissions, not app code. Check SharePoint first, always.

Confidentiality is enforced here, not in the app. The financial analysis subfolder and the margin columns are the sensitive zone: finance, the executives, and admins. Sales sees the price they entered, never the margin breakdown. Legal sees documents for legal review, not the money. If the app ever leaked a control by mistake, SharePoint still blocks the data.

### Layer 1 automated: per record permissions

The static grid above is the baseline for a list. A build with real confidentiality needs it per record too: sales rep A must not see the deal record, folder, or file rows that belong to sales rep B, even though both have Contribute on the same list. A flat SharePoint permission cannot express that, so a flow does it dynamically.

Shape proven in production, an automated flow (not app called) triggered on the main list's created or modified event:

1. Trigger: SharePoint "When an item is created or modified" on the record list.
2. `Break role inheritance` on the item (via the SharePoint REST HTTP action, see below), clearing sub scopes.
3. Grant the item to: the standing groups (site owners, the approvers group) and the record's own person columns (sales rep, architect, finance lead, plus the item's author so a record is never orphaned before people are picked). Skip blank person columns, and de duplicate first, one person can hold two roles.
4. If a subordinate folder already exists for the record (an idempotency flag, same pattern as folder creation), break inheritance on that folder too, then re break a further nested confidential subfolder with a narrower grant list (finance lead plus the approvers group plus owners, nobody else).
5. A second automated flow does the same thing for the file index list, triggered on that list's created or modified event, looked up against the parent record for its person columns. Rows filed under the confidential subfolder get the narrow grant, everything else gets the record team.

Because this runs on every edit, changing who is on a record (swap the finance lead) re syncs the grants automatically, no separate step needed. The consequence that falls out for free: SharePoint security trimming then scopes every browse gallery, dashboard, and KPI tile in the app to what the signed in user can actually open. A person filter in the app formula becomes redundant, the data source itself only returns what that user holds a grant on.

Known limits to write down, not surprises to rediscover: there is a short window (seconds) between a record being created and the flow locking it down. The flow re running on every edit is a feature, not a bug, but it means a manual SharePoint permission change on one item gets clobbered on the next edit, so permission changes belong in the flow's grant list, not clicked by hand.

`clearSubscopes=true` on a parent folder is the trap inside that feature. It resets the unique permissions of everything beneath the folder, so a confidential subfolder that the same flow locks down later in its run is inherited and readable by the whole team for the seconds in between. Because the flow re runs on every edit of the record, that window reopens on every save, which makes it predictable rather than rare. Use `clearSubscopes=false` when a child item carries its own tighter grants, or re lock the child before granting the parent.

The SharePoint REST calls used inside the flow (via the generic HTTP action against `_api/web/...`), reusable on any list:

```
POST _api/web/lists/getbytitle('{List}')/items({id})/breakroleinheritance(copyRoleAssignments=false,clearSubscopes=true)
POST _api/web/lists/getbytitle('{List}')/items({id})/roleassignments/addroleassignment(principalid={id},roledefid={roleDefId})
POST _api/web/ensureuser   body: { "logonName": "i:0#.f|membership|<email>" }
GET  _api/web/sitegroups/getbyname('{GroupName}')?$select=Id
GET  _api/web/associatedownergroup?$select=Id
```

`roledefid` is the numeric role definition id, the common ones are Full Control (1073741829), Contribute or Edit (1073741830, matches the "Edit" level in most site templates), Read (1073741826). Look these up per site once, they can drift by SharePoint template.

`associatedownergroup` returns the site's built in Owners group, not everyone who happens to hold Full Control. A security group added straight to the site with Full Control is not a member of that group, so every item level grant built on `associatedownergroup` skips it. Those people keep full access to the site while losing access to each locked item, which reads as a permissions bug and is not one. Put admins and service accounts inside the Owners group itself rather than granting them Full Control directly.

Pick the grant level per list, not by habit. A list the app only reads for gating (an approvals list whose rows a step gate counts) should grant the record team Read, not Edit. Read keeps the rows visible so the count stays correct, and stops a curious user editing a decision straight in SharePoint. Locking such a list away from the team entirely is worse than leaving it open, because the app's count then returns zero and the gate opens.

### Layer 1, confidential submission without read access: the drop box flow

A different problem from record visibility: letting someone submit into a folder they must never be able to read back, not even their own submission (a sensitive report the submitter should hand off but not retain). The instant, app called upload flow (references/flows.md shape 2) normally runs as the invoker, so the uploader needs Contribute on the target folder, which is exactly the access being withheld.

The fix is a second, near identical upload flow whose SharePoint connection is embedded (bound to the flow owner) instead of the usual invoker connection. Same trigger shape, same inputs, same actions as the normal upload flow. The only difference is the connection reference's `runtimeSource`, `embedded` instead of `invoker`. The app calls this flow instead of the normal one whenever the target subfolder is the confidential one, same `.Run()` signature, so the app side branching is a single `If` on the subfolder value:

```
If(varTargetSubfolder = "Financial analysis",
    UploadConfidential.Run(...same args...),
    UploadDocument.Run(...same args...))
```

Because the connection is embedded, the flow uploads as the maker regardless of who clicked the button in the app. The uploader needs zero SharePoint access to the folder, submits blind, and cannot browse back to see it, not even their own file. Pair this with the per record permission flow above, which locks the confidential subfolder down to the narrow grant list, and the loop closes: broad submission, narrow read.

### Layer 2: app gates. UX, not security.

Inside the app, gates decide what renders and what is enabled. They prevent confusion and accidents. A user with list Contribute could bypass the app entirely, so never treat an app gate as a security boundary.

The standard edit gate shape, computed in OnVisible per step:

```
Set(varStep5_CanEdit,
    !IsBlank(varDeal) &&
    !Coalesce(varDeal.Is_Locked, false) &&
    (
        varUserEmailLower = Lower(Coalesce(varDeal.Sales_Owner.Email, "")) ||
        varUserEmailLower = Lower(Coalesce(varDeal.Lead_Architect.Email, "")) ||
        varUserEmailLower = Lower(Coalesce(varPMODirector.Email, "")) ||
        (!IsBlank(varDeal.Project_Manager) &&
         varUserEmailLower = Lower(Coalesce(varDeal.Project_Manager.Email, "")))
    ));
```

Note the lock term: once locked, even authorized editors lose write access. Every edit gate carries it.

### Who sees which records

Two scopes, computed once and reused:

```
// global scope: admins and global role holders see everything
Set(varIsAdminOrGlobalRole,
    !IsBlank(LookUp(Role_Config, Role_Name.Value = "Admin"
        && Lower(Assigned_To.Email) = varUserEmailLower))
    || varUserEmailLower = Lower(Coalesce(varServicesDirector.Email, ""))
    || varUserEmailLower = Lower(Coalesce(varPMODirector.Email, ""))
    || varUserEmailLower = Lower(Coalesce(varCOO.Email, "")));

// per record relevance: on the record in any capacity
Set(varIsRelevantToDeal,
    !IsBlank(varDeal) && (
        varIsAdminOrGlobalRole ||
        varUserEmailLower = Lower(Coalesce(varDeal.Sales_Owner.Email, "")) ||
        varUserEmailLower = Lower(Coalesce(varDeal.Lead_Architect.Email, "")) ||
        varUserEmailLower = Lower(Coalesce(varDeal.Project_Manager.Email, "")) ||
        /* ... each working SME person column ... */
        CountRows(Filter(Reviews, Deal.Id = varDeal.ID &&
            Lower(Assigned_To.Email) = varUserEmailLower)) > 0));
```

Browse galleries filter on these: regular users see the records they are on, global roles see all.

### The admin philosophy (non negotiable)

Elevated visibility is not elevated authority. `varIsAdminOrGlobalRole` grants exactly three things: see all records in the browse views, see all reviews, and use the reset cycle button. It does not appear in step edit gates, it does not bypass evidence gates, it does not approve on anyone's behalf. Admins inside a record work under the same gates as everyone else. Any future feature that needs admin access references the flag explicitly in its own gate. Never make it a global bypass.

### Locking

The end of every record is a lock. `Is_Locked: true` plus `Locked_By` and the archive date, behind a confirm. Every edit gate and every flow respect it. Two calibrations proven in production:

- Hard lock: permanent, unlocking requires IT touching SharePoint directly. For audit grade records.
- Soft lock: anyone on the record, the approvers, or an admin can lock, an Undo appears right after, who locked is recorded (who unlocks is not). For processes where trust plus a record of who locked is enough.

Pick the calibration per process, deliberately, and write it down.

### Debugging permissions

| Symptom | Likely cause |
|---|---|
| Record missing from the browse view | User is on no role or reviewer row for it and is not a global role |
| "You don't have permission" on Save | Missing Contribute on the SharePoint list. Fix in SharePoint |
| Edit stays disabled for a just assigned person | Gate recomputes on OnVisible. Navigate away and back |
| Approve button disabled for an approver | Not their row, wrong cycle, or the record is locked |
| Combo shows last cycle's approver | Missing cycle filter in DefaultSelectedItems (the `powerapps-powerfx` skill Rule 8) |
| Admin cannot edit a step | By design. Visibility, not authority |
| A newly assigned person still cannot see the record, even hours later | The per record permission flow only runs on that record's own created or modified event. Open and save the record once to re-trigger it, or check the flow's run history for a failure |
| A person removed from a record's team can still open it | The flow re-syncs grants on every edit, so a stale grant survives until the record is edited again after the removal. Not automatic on person column removal alone if nothing else changed the item |
| An approver added to the roles list still cannot see any records | The roles list row controls what the app assigns. Seeing records is controlled separately by the SharePoint group behind Layer 1 automated. Add the person to both |
