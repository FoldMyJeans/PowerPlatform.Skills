# 06: Power Fx rules and gotchas. The non negotiable physics

Every one of these cost real debugging time on a real build. They are written as wrong versus right so they can be applied mechanically. When code violates one of these, fix it and cite the rule.

---

## Writing to SharePoint

### Rule 1: Never patch raw values into Choice or Lookup columns

```
// WRONG: generic "Network Error", brutal to debug
Patch(Deals, rec, { Current_Step: "5" })
Patch(Deals, rec, { Current_Step: 5 })

// RIGHT: pass a record with Value
Patch(Deals, rec, { Current_Step: { Value: "5" } })

// ALSO RIGHT: validated choice record
Patch(Deals, rec, { Current_Step: LookUp(Choices(Deals.Current_Step), Value = "5") })

// Lookup columns want Id plus Value
Patch(Docs, Defaults(Docs), { Deal: { Id: varDeal.ID, Value: varDeal.Deal_Reference } })
```

For Person columns, pass the whole Person record (`cmb_Picker.Selected` or a Person value read from another row). Never an email string.

### Rule 2: `Defaults(List)`, never `Blank()`, for record variables you will patch

```
// WRONG: "Incompatible Type". Blank() has no schema.
Set(varRecord, Blank());  Patch(List, Defaults(List), varRecord)

// RIGHT: Power Apps knows the record shape
Set(varRecord, Defaults(List));  Patch(List, varRecord, { ... })
```

Seed typed defaults in OnStart for any record or person variable used in patches, for example `Set(varPMDefault, Defaults(Role_Config).Assigned_To)`.

### Rule 3: Patch, then re-fetch. Always.

```
Patch(Deals, LookUp(Deals, ID = varDeal.ID), { ... });
Set(varDeal, LookUp(Deals, ID = varDeal.ID));   // MANDATORY
```

The local record variable does not update itself. Every patch is followed by the re-lookup, no exceptions.

### Rule 4: Every step moving patch carries the full stamp

```
Patch(Deals, LookUp(Deals, ID = varDeal.ID), {
    Current_Step: { Value: "5" },
    SubStep: { Value: "A" },        // always reset, unless explicitly moving to "B"
    Last_Updated_On: Now()
});
Set(varDeal, LookUp(Deals, ID = varDeal.ID));
```

`Last_Updated_On` on every patch, no exceptions. `SubStep` reset on every step change so a record never arrives at step 5 still carrying "B".

### Rule 5: Shared state is patched, never UI only

```
// WRONG: app loses state on refresh
Set(varStep3_SubStep, "B")

// RIGHT: SharePoint is truth, the variable is a mirror
Patch(Deals, LookUp(Deals, ID = varDeal.ID),
    { SubStep: { Value: "B" }, Last_Updated_On: Now() });
Set(varStep3_SubStep, "B");
```

If two users must agree on it, it lives in a column. Mirrors get rehydrated in OnVisible (05_APP_ARCHITECTURE.md in the `powerapps-architecture-and-ui` skill).

### Rule 6: One writer per column

A column written by a flow is never also written by the app, and the reverse. The reader side only reads. When the app patched a notification flag that the flow also patched, the result was a race. Decide the owner for every new column and record it in the data model doc. The one allowed exception: the app may set the initial value when it creates the row, after that only the owner writes.

### Rule 7: Wrap multi patch saves and flow calls in IfError

```
Set(varSendNotification_Ready, false);
IfError(
    // try: all patches, refresh, re-fetch, restart the debounce, success toast
    Patch(...); Patch(...);
    Refresh(Approvals);
    Set(varDeal, LookUp(Deals, ID = varDeal.ID));
    Set(varSendNotification_TimerStart, false);
    Set(varSendNotification_TimerStart, true);
    Notify("Saved.", NotificationType.Success),

    // catch: undo the gate so the UI is not stuck, red toast
    Set(varSendNotification_Ready, true);
    Notify("Save failed: " & FirstError.Message & " Refresh and try again.", NotificationType.Error)
)
```

A sequence of patches followed by an unconditional green toast is a silent failure generator. The catch must also reset any gate variable the try set, or the user is left staring at a permanently disabled button.

## Reading and querying

### Rule 8: Cycle scoped queries must filter on the cycle. Every single one.

```
// WRONG: returns stale approvals from previous rejection cycles
Filter(Approvals, Deal.Id = varDeal.ID && Step_Number.Value = "7")

// RIGHT
Filter(Approvals, Deal.Id = varDeal.ID
    && Step_Number.Value = "7" && Review_Cycle = varDeal.Review_Cycle)
```

Applies to every lookup, count, gallery Items, and, the sneaky one, every combo box `DefaultSelectedItems` that pre-fills from a reviews row. Missing the cycle filter on a combo default means that after a rejection the picker silently shows the previous cycle's approver.

### Rule 9: Yes/No columns read through Coalesce

`Coalesce(varDeal.Is_Locked, false)`. Rows created before the column existed return blank, and blank is not false in a boolean expression.

### Rule 10: Case insensitive email comparison, defensively coalesced

```
Lower(Coalesce(ThisItem.Assigned_To.Email, "")) = varUserEmailLower
```

Cache `Set(varUserEmailLower, Lower(User().Email))` once in OnStart and again in OnVisible. Every permission check uses the cached value.

## Type system traps

### Rule 11: An untyped `Table()` default poisons the whole expression

```
// BROKEN: "Name isn't valid. 'r' isn't recognized" plus cascading Patch errors
ForAll(
    Switch(varView,
        "FULL_FLOW", Table({ r: "President" }, { r: "COO" }),
        Table()                      // untyped default kills column r
    ) As role,
    Patch(List, Defaults(List), { Role: { Value: role.r } })
)

// FIXED: type the default with the same columns
        Table({ r: "" })
```

Power Fx type checks statically, so the column must exist in every branch even if that branch never runs. Same rule for gallery `Items` and any inline table consumed with `As`.

### Rule 12: Use an `As` alias for row scope over inline tables

Bare field names inside `Concat`, `LookUp`, `ForAll` over inline tables often fail to resolve:

```
Concat(steps As s, s.n & ". " & s.lbl, Char(10))
LookUp(steps As s, s.n = cur).lbl
```

### Rule 13: Modern and Classic text inputs read differently

| Family | YAML identifier | Read the typed value |
|---|---|---|
| Classic | `Classic/TextInput@2.3.2` | `txt_Foo.Value` |
| Modern | `ModernTextInput@1.0.0` | `txt_Foo.Text` |

Wrong property on Modern throws "The name 'Value' is not recognized". Wrong property on Classic returns an empty string silently, which is worse. If Studio offers to upgrade a classic control to modern, every reference in the app must be migrated in the same pass: DisplayMode formulas, patches, validation, HtmlViewer logic.

## Controls

### Rule 14: `ResetForm()` for attachment controls, not `Reset()`

```
// WRONG: file stays in the browser cache, second upload resends the first file
Reset(att_Step2_Files)

// RIGHT: clears the form context and the file cache
ResetForm(frm_Step2_MeetingNotesUpload)
```

`Reset()` per control is still right for the plain text inputs next to the upload (link name, link URL). Only the attachment control needs its parent form reset.

### Rule 15: HtmlViewer is display only

It renders HTML beautifully and cannot fire Power Fx on click. Anything clickable is built from real controls: a horizontal gallery of buttons, or transparent rectangles overlaid on the HTML tiles as click targets (`htm_StepTile` for the looks, `rec_StepClick` on top for the click).

### Rule 16: No control chains inside HtmlViewer text

An HtmlViewer whose `HtmlText` references another control's property, which itself depends back on the HtmlViewer, throws "Circular dependency" at load. Compute the text in OnVisible, store it in a variable, reference the variable. Referencing variables and collections inside `HtmlText` is fine.

### Rule 17: Theme through the variable

`Fill: =varTheme.Primary`, never a hardcoded RGBA. Exceptions: CSS inside HtmlViewer, deliberate gradients. After editing OnStart, Run OnStart in Studio or every themed control renders blank.

## Flows from the app

### Rule 18: `.Run()` argument order follows the trigger's required array

Inputs appear in the flow JSON as `text`, `text_1`, `text_2`, `number`, `file`. The app passes them positionally in the order of the trigger schema's `required` array, optional inputs (like a file) last. Full anatomy in 09_FLOWS.md in the `powerapps-approvals-and-flows` skill.

### Rule 19: "received 9, expected 7-8" is a cache, not your code

The app stored an old copy of the flow's signature. Studio: Power Automate pane, remove the flow, re-add it. Then the argument count matches. Any time a flow's inputs change, every app using it needs this refresh.

The cache holds the outputs too, not just the inputs, and that version is much harder to recognise. Change what a flow's Response action returns and the app keeps compiling against output names that no longer exist, so red errors appear on a button nobody edited, often right after some unrelated flow was re-added and quietly refreshed the signature. Same fix, remove and re-add. The diagnostic order is what matters: when a formula that calls a flow suddenly errors, read the flow's Response action body before changing one character of the formula.

### Rule 20: Wrap flow calls, then re-fetch

```
IfError(
    With({ result: CreateFolder.Run(varDeal.Customer, varDeal.Deal_Reference,
                                    varDeal.Route.Value, Text(varDeal.ID)) },
        Patch(Deals, varDeal, { Folder_Created: true, Folder_Link: result.folderpath })
    );
    Set(varDeal, LookUp(Deals, ID = varDeal.ID));
    Notify("Folder created.", NotificationType.Success),
    Notify("Could not create the folder. Check the flow run history.", NotificationType.Error)
)
```

`With` captures the flow's response record so the returned fields can be used in the same expression.

## URLs

### Rule 21: Encode anything user named that goes into a URL

```
// WRONG: breaks on spaces and special characters
Launch(".../Shared Documents/" & varDeal.Client_Name & ...)

// RIGHT
Launch(".../Shared%20Documents/" & EncodeUrlComponent(varDeal.Client_Name) & ...)
```

Client names contain spaces, ampersands and apostrophes. Flow side string building that only replaces spaces with %20 will still break on `&` and `'`, so treat cleanup of those characters as part of saving the name.

### Rule 22: Patch the record you just fetched, not the one you are holding

`Patch(List, record, {...})` sends that record's version tag, and SharePoint rejects the write if the row changed since the app loaded it. The failure is `Network error when using Patch function: Conflicts exist with changes` and it is a different problem from the Choice or Lookup type error that produces a similar message.

Automated flows are what make this routine rather than rare. Any flow that stamps a column on the record behind the user (a guard that writes an approved baseline, a notifier that sets a sent flag) bumps the row version a minute after the user's own save. The user's next save on the same screen then fails, and nothing about the app looks broken. On a build where a guard flow seeds a baseline on first save, this hits every new record.

```
// WRONG, writes against whatever the app loaded earlier
Patch(Deals, varDeal, { Contract_Value: Value(txt_Value.Text) });

// RIGHT, fetches the row at the moment of saving
Patch(Deals, LookUp(Deals, ID = varDeal.ID), { Contract_Value: Value(txt_Value.Text) });
Set(varDeal, LookUp(Deals, ID = varDeal.ID));
```

Apply it to every button that patches the open record, saves, locks, and step moves alike. Re-fetching after the patch is not enough on its own, because the background stamp lands later than that refresh.

## Verification

### Rule 23: A clean pack is not a clean app

`pac canvas pack` checks structure and control schema, not Power Fx types or scopes. The Formulas and errors panel in Studio after import is the real correctness check. Open it every time, clear every red.
