# Power Fx rules and gotchas. The non negotiable physics

Every one of these cost real debugging time on a real build. They are written as wrong versus right so they can be applied mechanically. When code violates one of these, fix it and cite the rule. Rules 14 to 21 and 27 (controls, flow calls, URLs) live in `references/controls-and-flow-calls.md`. Rules keep the number they were born with, so numbers jump inside a section.

---

## Writing to SharePoint

### Rule 1: Never patch raw values into Choice or Lookup columns

```
// WRONG: generic "Network Error", brutal to debug
Patch(Deals, rec, { Status: "Waiting for approval" })

// RIGHT: pass a record with Value
Patch(Deals, rec, { Status: { Value: "Waiting for approval" } })

// ALSO RIGHT: validated choice record
Patch(Deals, rec, { Status: LookUp(Choices(Deals.Status), Value = "Waiting for approval") })

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
    Current_Step: 5,                // a Number column in the example schema
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

If two users must agree on it, it lives in a column. Mirrors get rehydrated in OnVisible (the `powerapps-architecture-and-ui` skill).

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

### Rule 26: Update many rows with one batch Patch, not a ForAll that patches the list it reads

```
// WRONG: ForAll reads Approvals and patches Approvals inside the loop. Studio rejects it
ForAll(Filter(Approvals, Deal.Id = varDeal.ID && Step_Number.Value = "7"
        && Review_Cycle = varDeal.Review_Cycle && Decision.Value = "Pending") As r,
    Patch(Approvals, r, { Decision: { Value: "Returned" } }))

// RIGHT: base rows plus a table of changes, one call
With({ rows: Filter(Approvals, Deal.Id = varDeal.ID && Step_Number.Value = "7"
                    && Review_Cycle = varDeal.Review_Cycle && Decision.Value = "Pending") },
    Patch(Approvals, rows,
        ForAll(rows As r, { Decision: { Value: "Returned" }, Decided_On: Now(),
            Comment: If(Lower(Coalesce(r.Assigned_To.Email, "")) = varUserEmailLower,
                Trim(txt_ReturnReason.Text), "Auto-closed due to a return in this cycle") })))
```

The batch form is also one round trip instead of one per row. The return loop's auto close in the `powerapps-approvals-and-flows` skill is this shape.

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

### Rule 24: `Choices` on a Person column needs search text to reach the directory

`Choices(Deals.Sales_Owner)` returns only the first few dozen people (about 28 on a real tenant), not the directory. `Choices(Deals.Sales_Owner, txt_S1_OwnerSearch.Text)` searches the whole directory for the typed text. So a people picker with no search text lists a sample, and a `LookUp(Choices(Deals.Sales_Owner), ...)` can only find someone inside that sample. To find a person, pass text. That search text is also what breaks in a people picker shipped from source, see the `powerapps-source-workflow` skill.

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

### Rule 13: Read a text input with `.Text`, in either family

| Family | YAML identifier | Read the typed value |
|---|---|---|
| Classic | `Classic/TextInput@2.3.2` | `txt_Foo.Text` |
| Modern | `ModernTextInput@1.0.0` (the version moves, copy it from your unpacked source) | `txt_Foo.Text` |

Neither has a `.Value` output, so a formula reading `.Value` fails with a name not recognized error. The modern controls were refreshed from February 2026 with renamed properties (`FontColor` to `Color`, `FontSize` to `Size`) and enum values (`Align.Left`), and the modern text input's `OnChange` now fires on leaving the box. If Studio offers to update or upgrade a control, migrate every reference to it in the same pass: DisplayMode formulas, patches, validation, HtmlViewer logic, and any YAML generator that writes it.

### Rule 25: IfError's fallback must match the value's type

Two argument `IfError(value, fallback)` returns the type of the value. A fallback of another type is a compile error. Rule 7's shape already obeys this, both of its branches end in `Notify`.

```
// WRONG: Patch returns a record, Notify returns a boolean
IfError(Patch(Deals, LookUp(Deals, ID = varDeal.ID), { Last_Updated_On: Now() }),
    Notify("Save failed: " & FirstError.Message, NotificationType.Error))

// RIGHT: end the value chain with true, so both sides are boolean
IfError(Patch(Deals, LookUp(Deals, ID = varDeal.ID), { Last_Updated_On: Now() }); true,
    Notify("Save failed: " & FirstError.Message, NotificationType.Error))
```

## Write conflicts

### Rule 22: Patch the record you just fetched, not the one you are holding

`Patch(List, record, {...})` sends that record's version tag, and SharePoint rejects the write if the row changed since the app loaded it. The failure is `Network error when using Patch function: Conflicts exist with changes` and it is a different problem from the Choice or Lookup type error that produces a similar message. Automated flows are what make this routine rather than rare. Any flow that stamps a column on the record behind the user (a guard that writes an approved baseline, a notifier that sets a sent flag) bumps the row version a minute after the user's own save. The user's next save on the same screen then fails, and nothing about the app looks broken. On a build where a guard flow seeds a baseline on first save, this hits every new record.

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

`pac canvas pack` does not validate property names, YAML syntax, or Power Fx types and scopes. Loading the app in Studio and reading the Formulas and errors panel is the real correctness check. Open it every time, clear every red.
