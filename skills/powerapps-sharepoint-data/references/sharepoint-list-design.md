# SharePoint as the database. List design that holds up

The lists are the real application. The canvas app is a coordinator on top of them. Design the lists first, build them first, and write the app against their confirmed names.

---

## The standard four list shape

Every app built with this method has landed on the same four lists. Start every new app from this shape and adjust:

| List | Grain | Example name |
|---|---|---|
| Main record | One row per deal, request, or case | `Rev_Deals` |
| File index | One row per uploaded file or registered link | `Rev_DealFiles` |
| Approvals / reviews | One row per approver, per record, per cycle | `Rev_Approvals` |
| People and roles | One row per standing role, pointing at a person | `Rev_RoleConfig` |

The formulas throughout these docs use the short unprefixed names (`Deals`, `Deal_Files`, `Approvals`, `Role_Config`) for readability. In a real app, apply the prefix rule below to all of them.

Plus one document library with a per record folder structure (created by a flow, see the `powerapps-approvals-and-flows` skill).

## Naming rules (these prevent whole classes of bugs)

1. Prefix every list with the app's short code (`Rev_`, `Sow_`, whatever fits). One place to find them, no collisions with other apps on the site.
2. No spaces in column names, ever. SharePoint keeps a hidden internal name fixed at creation. Formulas bind to internal names. If the display name has no spaces, internal and display stay identical forever, and a later rename can never silently break the app. `Current_Step`, `Is_Locked`, `Review_Cycle`, `Last_Updated_On`.
3. One row per fact. An approval is one row per approver per cycle, not columns on the main record. A file is one row in the index. Facts as rows give you audit trails and clean queries for free.
4. Keep on the row only what the app acts on: routing, gating, notifications, dashboards, folder naming. Detailed content stays in documents in the record's folder. Do not retype documents into columns.
5. Anything that might feed a dashboard is a real typed field (Number, Currency, Date, Choice), never free text. You cannot chart free text.

## Column types and how Power Fx touches them

| SharePoint type | Read in Power Fx | Write in Patch |
|---|---|---|
| Single line text | `record.Field` | `Field: "text"` |
| Multiple lines | `record.Field` | `Field: "text"` |
| Choice | `record.Field.Value` | `Field: { Value: "Approved" }` |
| Person | `record.Field.DisplayName`, `.Email` | the whole record: `Field: cmb_Picker.Selected` |
| Lookup | `record.Field.Id`, `.Value` | `Field: { Id: 42, Value: "Title text" }` |
| Number / Currency | `record.Field` | `Field: Value(txt_Input.Text)` |
| Date | `record.Field` | `Field: dp_Picker.SelectedDate` or `Now()` |
| Yes/No | `Coalesce(record.Field, false)` | `Field: true` |
| Hyperlink | `record.Field` | `Field: "https://..."` |

Two of these cause most patch failures. Never patch a raw string or number into a Choice or Lookup column (you get a useless generic network error). Never write a Person column from an email string, pass the Person record. Full rules in the `powerapps-powerfx` skill.

Practical type notes from the builds:

- Date columns: time off for business dates (submitted, decided, archived), time on only for true timestamps (`Last_Updated_On`). A time off column is stored as midnight UTC, so never run one through `convertTimeZone` in a flow. Converting midnight UTC to a western timezone lands on the previous evening, and the date prints as the day before. Format it as it is with `formatDateTime(<column>, 'yyyy-MM-dd')`, and reserve `convertTimeZone` for real timestamps like `utcNow()`. Fall back like this when the column can be empty: `if(empty(coalesce(<column>, '')), convertTimeZone(utcNow(), 'UTC', '<Local Time Zone>', 'yyyy-MM-dd'), formatDateTime(<column>, 'yyyy-MM-dd'))`.
- Percent fields as whole numbers (35 means 35 percent). Simpler than SharePoint percent formatting.
- Yes/No columns default No, and every read wraps in `Coalesce(x, false)` because pre-existing rows return blank, not false.
- A `Title` column is mandatory on every list. Either auto fill it from the app (set it to the record reference) or ignore it. Never surface it as a user field.
- Add Lookup columns last when building a list that looks up into itself.

## The main record list

Columns cluster into groups. Every formula in these skills is written against the columns
below, so an example copied from another skill binds without edits.

| Group | Column | Type | Notes |
|---|---|---|---|
| Identity | `Deal_Reference` | Text | The human readable record number. Used in folder names and email subjects |
| | `Customer` | Text | The client or requester name |
| | `Route` | Choice | Which variant of the process this record follows |
| People on the record | `Sales_Owner`, `Lead_Architect`, `Project_Manager` | Person | Per record roles, picked from the whole directory, not from the roles list |
| | `Owner_Email` | Text | Lowercased mirror of `Sales_Owner`, written in the same patch. The delegable filter, see Delegation reality below |
| Position in the process | `Current_Step` | Number | Starts at 1 |
| | `Status` | Choice | The overall state shown on dashboards |
| | `SubStep` | Choice | A or B, only if steps have sub phases |
| | `Review_Cycle` | Number | Starts at 1, increments on every return |
| | `Max_Step_Reached` | Text | Forward only, only if you gate free navigation |
| Headline numbers | `Contract_Value`, `Margin_Given_Up` | Currency or Number | Whatever the dashboards chart |
| Dates | `Last_Updated_On` | Date, time on | Stamped by every patch |
| | submitted, target, decision, archived | Date, time off | Cycle time KPIs |
| Folder and locks | `Folder_Link` | Hyperlink | Written once by the folder flow |
| | `Root_Folder_Url` | Text | The record's folder path. Written by the folder flow, read by the upload flow |
| | `Folders_Created` | Yes/No | Idempotency flag for the folder flow |
| | `Is_Locked`, `Locked_By` | Yes/No, Person | Set when the record finishes |
| Notification flags | `<Event>_Notification_Sent` | Yes/No | One per send once event. Owned by flows, never patched by the app |
| | `Last_Notified_On`, `Last_Notified_PM_Email` | Date, Text | Only what the re-send suppression needs. See the `powerapps-approvals-and-flows` skill |

Swap the nouns for your own process, but keep one name per concept. The cost of two names for
one column is paid later, in formulas that look right and bind to nothing.

Step numbering choice: a Number column is simpler to compare and increment. A Choice of strings ("1" to "8") reads better in SharePoint views but forces `{ Value: "5" }` syntax and `Value()` conversions everywhere. Either works. Pick one per app and never mix.

## The file index list ("files are truth")

The app never queries the document library directly. Every upload flow writes one row here, and every evidence gate counts rows here:

| Column | Type | Notes |
|---|---|---|
| `Deal` | Lookup to main list | Set by the flow from the record ID |
| `File_Name` | Text | Original name, or link name with `.url` appended |
| `Folder_Category` | Choice | Which subfolder it went to. Drives per step galleries and gates |
| `Document_Category` | Choice | What kind of document it is. Only if that axis matters separately, see below |
| `Document_URL` | Hyperlink | Opens the file via `Launch()`. Written by the flow |
| `Step_Number` | Choice | Which step it was uploaded at |
| `Is_Link` | Yes/No | Link registration vs real file |
| `Uploaded_By` | Person | Set by the flow from the invoker email |
| `Uploaded_On` | Date | `utcNow()` in the flow |

A gate is then one honest count:

```
CountRows(Filter(Deal_Files,
    Deal.Id = varDeal.ID && Folder_Category.Value = "02 Architecture")) > 0
```

Keep the category axis (what kind of document) separate from the subfolder axis (where it lives) if both matter. Carry `Document_Category` and `Folder_Category` as separate Choice columns rather than overloading one.

## The people and roles list

One row per standing role, pointing at the person who holds it now:

| Column | Type | Notes |
|---|---|---|
| `Title` | Text | Readable label |
| `Role_Name` | Choice | The fixed role vocabulary for the process, for example: Finance, President, COO, CFO, VP of Sales, Legal, Admin |
| `Assigned_To` | Person | Who holds it right now |

Multiple rows per role are allowed (several Finance users, several Admins). The app reads it in OnStart:

```
Set(varCOO, LookUp(Role_Config, Role_Name.Value = "COO").Assigned_To);
```

Changing an approver is one row edit. No app change, no flow change. This list must be seeded before the app first runs, because OnStart reads it. Per record people (sales rep, architect) are NOT in this list, they are person columns on the record, picked from the directory.

## The approvals list

One row per approver, per record, per cycle:

| Column | Type | Notes |
|---|---|---|
| `Deal` | Lookup | Back to the main record |
| `Approver_Role` | Choice | Which hat this row is |
| `Assigned_To` | Person | Who must decide |
| `Decision` | Choice | Pending, Approved, Returned (or Rejected) |
| `Comment` | Multiple lines | Required on return, optional on approve |
| `Assigned_On`, `Decided_On` | Date | The audit trail |
| `Step_Number` | Choice | Which step of the process assigned this row. Every cycle scoped query filters on it |
| `Review_Cycle` | Number | Matches the record's cycle counter |
| `Notification_Sent` | Yes/No | Owned by the notification flow |
| `Notification_Sent_On` | Date | Stamped by the same flow. Drives re-send suppression |

Full approval mechanics in the `powerapps-approvals-and-flows` skill.

## SCHEMA_AS_BUILT.md: the contract document

Keep one markdown file in the repo that lists the real lists, the real internal column names, the exact Choice values, and per column notes, updated as each list is built and confirmed. The app code is the consumer, this doc is the contract. Rules that make it work:

- Fill it in from the actual SharePoint list settings pages, not from the design intent.
- Record the site URL shape but keep the real tenant URL out of the committed doc (`https://<tenant>.sharepoint.com/sites/<Site>`, real value kept local).
- Record the list GUIDs once flows exist, because flow JSON references lists by GUID and changing a list means coordinated flow updates.
- Keep a "defined but unused" section per list for columns that exist but nothing reads or writes. Never invent uses for them silently, wire them or delete them deliberately.
- Choice values drift. SharePoint stores the options in the column config, not in your code. Before any code change that filters, patches, or switches on a Choice value, confirm the current values in SharePoint settings.

## Delegation reality

SharePoint delegation in Power Fx is partial and person column filters are non delegable. Two
separate ceilings get confused with each other, and only one of them is about delegation:

- The non delegable query row limit. When a query cannot fold to the server, the app pulls
  at most this many rows and silently computes over that subset. Default 500, raise it to
  2000 in App settings, General, Data row limit. It cannot go higher. Nothing errors when a
  query truncates. A count is simply wrong, and it stays wrong quietly as the list grows past
  the limit, which is why it usually surfaces months after launch.
- The list view threshold. SharePoint refuses to serve any query that would scan more than
  5000 items in a single list unless the filtered column is indexed. This is a server side
  limit, not a Power Apps one, and it applies to delegable queries too. SharePoint Online
  adds some indexes on its own, so plan the ones you need rather than assuming either that
  they appear or that they do not. Index the columns your filters touch while the list is
  still small, and confirm in list settings, Indexed columns.

What that means in practice:

- Keep the hot small lists small. A roles list has a dozen rows, an approvals list has a few per record. Non delegable filters over these are fine.
- For the main list, design dashboard galleries to bind directly to the data source with simple delegable filters where possible, then do the personal, non delegable checks (`Lower(Coalesce(Assigned_To.Email,"")) = varUserEmailLower`) per row or over already filtered sets.
- Decide early which queries must be delegable and shape columns for them. Index every column a delegable filter touches, and prefer a Choice or Number status column over a computed condition.
- When a person filter genuinely has to run server side, mirror the column. Add a plain single line text column and write the person's email into it in the same patch that writes the person column, already lowercased. The filter is then `Filter(Deals, Owner_Email = varUserEmailLower)`, delegable, a bare column compared with `=`. Wrapping the column in `Lower()` inside the Filter breaks delegation again and puts you back where you started, which is the whole reason the lowercasing happens on write and not on read. Backfill the mirror on existing rows or they silently drop out of every filtered view.

## Building the lists

Two workable ways, pick per project:

1. By hand against a printed spec. Reliable, tedious. The spec is the SCHEMA_AS_BUILT table written first as intent, then confirmed.
2. A PnP PowerShell script that creates each list and every column exactly. Faster for wide lists, needs the PnP module and site permission.

Do not use the Excel import shortcut. It guesses every column as text and you will rebuild the types by hand anyway. Choice and Person columns cannot be created reliably that way.

Order matters when lists reference each other. Build the people and roles list first (OnStart reads it), then the main list, then the file index and approvals (their Lookup columns need the main list to exist). Seed roles with at least an Admin row before first app run.
