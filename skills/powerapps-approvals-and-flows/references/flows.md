# Power Automate flows. Anatomy, proven shapes, and the skeleton first method

Flows do the three jobs the canvas app cannot: create SharePoint folders, write files, and send email. This doc covers how flow JSON is structured, the flow designs that shipped, and the low error way to author new ones.

---

## Ground rules

- Trigger: PowerApps (V2) for every app called flow, in the same environment as the app. Two automated flows are an exception, see the permission sync shape in references/approvals-and-permissions.md, they trigger on a SharePoint list's created or modified event, not from the app.
- Connections: `shared_sharepointonline` (SharePoint) and `shared_office365` (Outlook, Send an email V2), running as invoker by default, so files and emails carry the identity of the person who clicked. The deliberate exception is the drop box upload flow (references/approvals-and-permissions.md), whose connection is embedded on purpose so it runs as the maker instead of the invoker, letting someone submit into a folder they cannot read.
- One writer per column (the `powerapps-powerfx` skill Rule 6). Flow written columns (`Folders_Created`, `Root_Folder_Url`, `Notification_Sent` flags) are read by the app, never written by it.
- Idempotency flags so a re-run never duplicates (`Folders_Created: true` written back after folder creation).
- Deep link every email: append `&dealId=<record id>` (and optionally `&view=<step>`) to the app play URL so the recipient lands on the exact record.
- Prefer reusable flows. An early build shipped six upload flows and three notification flows, one per document type or event. The next build collapsed those into one parameterized upload flow and one notification flow. Fewer flows, fewer places to fix.

## Trigger anatomy (PowerApps V2)

The trigger schema names inputs by type and order: `text`, `text_1`, `text_2`, ..., `number`, `file`. The designer shows friendly titles (ClientName, DealNumber), the JSON keeps the generic keys:

```json
"triggers": {
  "manual": {
    "type": "Request",
    "kind": "PowerAppV2",
    "inputs": {
      "schema": {
        "type": "object",
        "properties": {
          "text":   { "title": "ClientName",   "type": "string" },
          "text_1": { "title": "DealReference","type": "string" },
          "number": { "title": "RecordID",     "type": "number" },
          "file":   { "title": "File Content", "type": "object",
                      "properties": { "name": { "type": "string" },
                                      "contentBytes": { "type": "string", "format": "byte" } } }
        },
        "required": ["text", "text_1", "number", "file"]
      }
    }
  }
}
```

Put every input in `required`, including the file. This is not tidiness, it is the difference between a working upload and a silent data loss bug.

An input left out of `required` may never arrive. Power Apps builds the request from the required set, so an optional file input gets dropped on the way out. The call still succeeds, the flow still runs, `@triggerBody()?['file']?['contentBytes']` resolves to nothing, and `CreateFile` writes the literal string `null`. Every uploaded document lands in SharePoint as a 4 byte file that will not open. Nothing errors anywhere. A build ran for a month like this before anyone tried opening an attachment, because the link path was unaffected and everyone used links.

The tell, if you are already in this hole: open the flow run, expand the trigger, and count the parameters in the body. Eight text fields and no `file` key means the app never sent it.

Argument order follows the schema, not the required array. Required inputs take their position in `properties`, so a `file` sitting between `text_4` and `text_5` is the sixth argument to `.Run(...)`, not the last one. Making a previously optional input required therefore shifts every argument after it, and the app formulas must move with it.

Change the inputs and every app using the flow must remove and re-add it in the Power Automate pane (the `powerapps-powerfx` skill Rule 19).

## Action anatomy

Every SharePoint action is an `OpenApiConnection` with the same skeleton:

```json
"Create_file": {
  "type": "OpenApiConnection",
  "inputs": {
    "parameters": {
      "dataset": "https://<tenant>.sharepoint.com/sites/<Site>",
      "folderPath": "@outputs('cmpTargetFolderPath')",
      "name": "@triggerBody()?['text_4']",
      "body": "@triggerBody()?['file']?['contentBytes']"
    },
    "host": {
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_sharepointonline",
      "operationId": "CreateFile",
      "connectionName": "shared_sharepointonline"
    }
  },
  "runAfter": { "cmpTargetFolderPath": ["Succeeded"] }
}
```

The parts that must be exactly right:

- `dataset` is the site URL. `table` (for list actions) is the list GUID, not the list name. Record the GUIDs in the schema doc, changing a list means coordinated flow updates.
- `operationId` names the operation: `CreateNewFolder`, `CreateFile`, `GetFileItem`, `PostItem` (create list item), `PatchItem` (update list item), `GetItem`, `GetItems`.
- `connectionName` in `host` matches the key in the flow's `connectionReferences` block, which maps to a connection reference logical name shaped like `<publisherprefix>_shared<connector>_<hash>`. Reuse the existing connection reference for new flows, never invent one.
- Every action in a solution flow carries `"authentication": "@parameters('$authentication')"` inside its parameters (the examples above omit it for brevity, real flows must have it).
- `runAfter` chains actions. An empty `runAfter {}` marks the first action.
- Person columns are written as a claims string: `"item/Uploaded_By/Claims": "@concat('i:0#.f|membership|', triggerBody()?['text_5'])"`.
- Choice columns write through `/Value`: `"item/Folder_Category/Value": "05 Meeting Notes"`. Lookup columns through `/Id`: `"item/Deal/Id": "@triggerBody()?['number']"`.
- `Compose` actions (`"type": "Compose"`) are the workhorse for string building. Name them `cmp<What>` and read them with `outputs('cmpName')`.
- Copying between sites with `CopyFileAsync` or `CopyFolderAsync`: `sourceFileId` and `sourceFolderId` take a double encoded site relative path, not the plain path and not a normally encoded one. Build it as `uriComponent(replace(replace(<path>, ' ', '+'), '/', '%2f'))`, so a slash arrives as `%252f` and a space as `%2b`. Either of the other two forms fails.
- Timestamps in file names go in as `yyyy-MM-dd HHmm`. Largest unit first, 24 hour, leading zeros, so the library's alphabetical sort is also chronological and stays that way forever. Colons are illegal in SharePoint file names, so never `HH:mm`. For local time: `convertTimeZone(utcNow(), 'UTC', 'Eastern Standard Time', 'yyyy-MM-dd HHmm')`.

Returning a value to the app makes the call synchronous and gives `.Run()` a result:

```json
"Respond_to_a_Power_App_or_flow": {
  "type": "Response", "kind": "PowerApp",
  "inputs": { "statusCode": 200,
    "body": { "folderpath": "@outputs('cmpFolderPath')" },
    "schema": { "type": "object",
      "properties": { "folderpath": { "type": "string" } } } }
}
```

The app reads it as `MyFlow.Run(...).folderpath`.

A Response whose `body` is `{}` returns nothing and does not error. The run goes green, `.Run()` hands back blanks, and the app patches those blanks straight over real values, a blank folder link being the usual casualty, while the formula still compiles fine against the cached schema. The schema and the body are two separate things and only the schema is checked. After any edit to a Response, confirm the body actually populates every property the schema declares.

## Proven flow shape 1: create record folders

Called by the app right after a record is created. Actions in order:

1. Compose the folder name from customer plus reference: `{Customer} - {Reference}`. Trim the inputs. Clean characters SharePoint rejects.
2. Optional bucketing for scale: compose the first character of the client name, map it to a bucket folder (`1-9`, `A-C`, `D-G`, `H-K`, `L-P`, `Q-S`, `T-W`, `X-Z`) with nested `if()` expressions, and nest the record folder inside the bucket. Skip buckets until a folder actually gets crowded.
3. `CreateNewFolder` for the record folder, then one per subfolder (a fixed standard set per app, for example Checklist, Financial analysis, Supporting documents).
4. Optionally copy the route's blank checklist from a master Templates library into the Checklist subfolder (Copy file action). Masters are never edited, only copied.
5. `PatchItem` back onto the main list: `Folders_Created: true`, `Root_Folder_Url`, plus `Last_Updated_On`. Or skip the write back and return the path for the app to patch (see the caution below).
6. `Response` returning `folderpath`.

Hard learned notes:

- `CreateNewFolder` errors if the folder already exists. To tolerate re-runs, chain the subfolder actions with `runAfter` accepting `["Succeeded", "Failed"]`. `CreateFile` by contrast auto creates missing intermediate folders and never errors on existing ones, which is why upload flows do not need the folder to exist first.
- Decide the write back owner deliberately. If the flow patches `Folders_Created`, the app must not. One production flow skipped the update item action, so its app patches the flag client side after `.Run()`:

```
IfError(
    With({ result: CreateDealFolder.Run(varDeal.Customer, varDeal.Deal_Reference,
                                        varDeal.Route.Value, Text(varDeal.ID)) },
        Patch(Deals, varDeal, { Folders_Created: true, Folder_Link: result.folderpath })
    );
    Set(varDeal, LookUp(Deals, ID = varDeal.ID));
    Notify("Deal folder created.", NotificationType.Success),
    Notify("Could not create the folder. Check the flow run history.", NotificationType.Error))
```

## Proven flow shape 2: upload a file or register a link

One flow handles both a real file and a URL registration, branching on whether the link input is empty:

Inputs: ClientName, Reference, FolderCategory, StepNumber, FileName, File (object), UploadedByEmail, RecordID (number), LinkUrl (text, empty means file). All of them required, and the File sits at its schema position, so it is the sixth argument and not the last.

The link path still has to pass a file object, and the value matters. An empty string on a `format: byte` field serialises to `null`, which a required schema rejects at the trigger with `TriggerInputSchemaMismatch: Expected String but got Null`. Pass a token instead, `{ name: "Link.url", contentBytes: "IA==" }`, which is base64 for a single space. The link branch never writes it, so the value is inert, it just has to be a real base64 string.

File branch:

1. `CreateFile` into the composed target path with `@triggerBody()?['file']?['contentBytes']` as the body. Set chunked transfer (`"runtimeConfiguration": { "contentTransfer": { "transferMode": "Chunked" } }`) so large files work.
2. `GetFileItem` to fetch the new file's metadata.
3. Compose the document URL: `coalesce` the `Link to item`, `{Link}`, and `Path` properties, then `@decodeUriComponent(first(split(url, '?')))`. The split strips the query string, the decode un-escapes %20. Both are load bearing: SharePoint Hyperlink columns cap at 255 characters and percent encoded long names overflow and fail with "Invalid URL value".
4. `PostItem` a row into the file index list: name, URL, category, step, lookup to the record, uploader claims, `utcNow()`.

Link branch:

1. Compose a Windows shortcut body: `[InternetShortcut]` newline `URL=<the link>` newline `IconIndex=0` (build newlines with `decodeUriComponent('%0D%0A')`).
2. Compose the shortcut name, appending `.url` unless already present.
3. `CreateFile` the shortcut, `GetFileItem`, `PostItem` the index row with the real target URL as `Document_URL`.

So a registered link is both a real clickable `.url` file in the folder and a row in the index. The app calls the same flow for both paths:

```
// files: loop the attachment control. The file object is the 6th argument.
ForAll(att_Docs_Files.Attachments As f,
    UploadDocument.Run(varDeal.Customer, varDeal.Deal_Reference, varDeal.Route.Value,
        Coalesce(varUploadSub, "Supporting documents"), f.Name,
        { name: f.Name, contentBytes: f.Value },
        User().Email, varDeal.ID, ""));
// links: same flow, URL filled, token file object
UploadDocument.Run(..., Trim(txt_LinkName.Text),
    { name: "Link.url", contentBytes: "IA==" },
    User().Email, varDeal.ID, Trim(txt_LinkUrl.Text));
// then, always:
Refresh(Deal_Files); ResetForm(frm_Docs_Upload); Reset(txt_LinkName); Reset(txt_LinkUrl)
```

`ResetForm`, not `Reset`, on the upload form (the `powerapps-powerfx` skill Rule 14).

## Proven flow shape 3: notify people

Two variants.

Simple recipients variant: the app computes a semicolon joined, deduplicated, lowercased recipient string (the `powerapps-architecture-and-ui` skill and references/approvals-and-permissions.md show the Concat and Distinct formulas) and the flow is just Send an email V2 to that string with subject, body, and the deep link. Inputs: RecordID, Reference, Customer, Recipients, AppLink. Start here.

Iterating variant (per row emails plus per row sent flags): the flow takes only RecordID and AppLink, does `GetItem` on the record and `GetItems` on the approval rows (`DealId eq {id} and Step_Number eq '7'`), then `Apply_to_each` row:

- Condition: the row has an email, belongs to the current cycle, and either was never notified or its stored context (a meeting date) changed since the last send.
- Send the email, addressing the person by their role with the underscores cleaned up, including the two deep links (app plus folder).
- `PatchItem` the row: `Notification_Sent: true`, `Notification_Sent_On: utcNow()`, plus the context that suppression compares against (the notified meeting date).

The suppression contract is shared with the app: the Send button's DisplayMode counts unsent rows with the same conditions, so the button greys exactly when the flow has nothing left to send, and re-arms when the date or person changes (the `powerapps-architecture-and-ui` skill). PM style single recipients on the record use the same idea with flags on the record: `PM_Notification_Sent`, `PM_Notification_Meeting_Date`, `Last_Notified_PM_Email`, re-send when any differ.

Email body notes: a short delay (5 seconds) before the send lets SharePoint settle after row creation. Build folder links by encoding the path (simple replace of spaces with %20 breaks on `&` and apostrophes, prefer proper encoding or clean the names at save time).

Set the importance explicitly. Send an email V2 sends at low importance when the parameter is absent, so recipients get a "Low importance" banner on an approval notice. Add `"emailMessage/Importance": "Normal"` to the action parameters.

Printing a date from a SharePoint date column: do not run it through `convertTimeZone`. See the `powerapps-sharepoint-data` skill for why that prints the day before.

## Proven flow shape 4: scheduled sweep

A daily recurrence trigger, `GetItems` with an OData filter (expiry date past, still active), one reminder email per hit. Used for ballpark estimate expiry reminders. Anything with a date column and a consequence can get one of these.

## The skeleton first method (how to author a new flow)

Hand authoring flow JSON from nothing fails on the invisible parts: GUIDs, connection references, the `$authentication` parameter on every action, exact SharePoint parameter formats. Some failures are silent until runtime. So never start from a blank file:

1. A human creates a skeleton in the Power Automate designer: the PowerApps V2 trigger with the inputs named and ordered, the connection wired to the existing connection reference, one placeholder action.
2. Export the solution (unmanaged) and unzip.
3. Author the real action logic by editing the flow's JSON. The trigger, connections, and auth boilerplate are now known good, and an existing flow in the same solution is the style reference for every action shape.
4. `pac solution unpack --zipfile <exported>.zip --folder <repo path>` the finished zip into the repo for version control, and import the solution back with `pac solution import --path <zip> --async --max-async-wait-time 8`. Unpack produces one `<FlowName>-<GUID>.json` plus a `.json.data.xml` sidecar per flow, both text, both diffable.

## Editing a flow that is already live

The same export and import cycle edits a running flow. It does not only fill in skeletons. This was believed impossible for about a week on one build, on the strength of a few imports that were accepted and changed nothing, and the wrong conclusion drawn was that the engine refuses to overwrite a live flow. It does not.

The missing ingredient is the solution's `<Version>`. Bump it by hand before rezipping. Without the bump the import succeeds, reports success, and leaves every flow exactly as it was.

The cycle:

1. Keep the canvas app out of the flow solution. It lives alone in an app-only solution (the `powerapps-source-workflow` skill), so a flow export and import stay small and fast and can never overwrite the app.
2. `pac solution export --name <SolutionName>` and unzip it. The `<Version>` element lives in `solution.xml` at the root of the exported zip, and in `Other/Solution.xml` once unpacked into a repo.
3. Edit `Workflows/<FlowName>-<GUID>.json` by hand.
4. Bump `<Version>`.
5. Rezip with `Compress-Archive`, zipping the folder contents and not the folder itself.
6. `pac solution import --path <zip> --async --max-async-wait-time 8` as an update to the existing solution.

The whole cycle is command line, so an agent can run it end to end without a human clicking through the maker portal. `--async` is what makes step 6 usable: without it the CLI prints nothing while it waits, which is easy to mistake for a hang. With it the import streams progress and returns in about four minutes.

Proven on 2026-07-29: four live flows were rewritten this way in one pass, and a verification export afterwards showed all ten flows in the solution byte matching what had been authored. That run still imported through the portal. The command line import leg was proven separately on 2026-08-08.

Two things to do after the import. Check that nothing came back deactivated, because an import can land a flow in the off state. And if any flow's Response output schema changed, remove and re-add that flow in every calling app's Power Automate pane, or the app keeps compiling against the old cached signature.

## Registering a flow in the solution by hand

When adding a flow JSON directly into an unpacked solution instead of through the designer:

1. Generate a new GUID for it.
2. Add `Workflows/<FlowName>-<GUID>.json` (the definition) and `Workflows/<FlowName>-<GUID>.json.data.xml` (the sidecar carrying the name, type, and state, copy an existing one and edit).
3. Add a root component to `Other/Solution.xml`: `<RootComponent type="29" id="{guid}" behavior="0" />` (type 29 is a cloud flow, type 300 is the canvas app).
4. Reuse the existing connection reference in the JSON's `connectionReferences` block.
5. `pac solution pack`, then `pac solution import --path <zip> --async --max-async-wait-time 8`.

This works and was done in production, but the skeleton first method above produces fewer surprises. Prefer it.

## Wiring the app to a flow

A `.Run()` only resolves after the flow is added to the app in Studio (the Power Automate pane). A YAML reference alone does not connect it, so the real `.Run()` wiring is part of the manual handoff (the `powerapps-build-playbook` skill). The proven interim: have the button patch the flag directly (`Patch(Deals, varDeal, { Folders_Created: true })`) so the gates and downstream UI can be tested before the flow exists, then swap in the real call in Studio. And after any flow signature change: remove and re-add the flow in the pane, or you get the argument count cache error.

## Connector and expression traps that only show up at activation or runtime

- **`overwrite` on `CreateFile` gets rejected when you try to turn the flow on.** An older SharePoint `CreateFile` action carrying `"overwrite": true` in its parameters imports fine, looks fine in the designer, and then fails with `WorkflowOperationParametersExtraParameter`, "The API operation does not contain a definition for parameter 'overwrite'" the moment you try to enable it. The connector retired the parameter. Fix: delete the `overwrite` key from every `CreateFile` action's parameters. The behavior change is real, not just a JSON tweak: uploading a file whose name already exists in the folder now errors instead of silently replacing it, so if silent replace was relied on, handle that case explicitly (rename, or check first with `GetFileItem`).
- **`createArray()` called with zero arguments throws at runtime**, not at save. A dedup pattern like `union(createArray(a, b, c), createArray())` (the empty call meant "no extra items") fails with `InvalidTemplate`, "'createArray' expects a comma separated list of parameters. The function was invoked with no parameters." `createArray()` needs at least one argument. Seed it with an empty string instead: `createArray('')`, then filter blanks out of the unioned result the same way you already filter blank emails or names.

- **`select` and `filter` are actions, not template functions.** Writing
  `select(body('Get_rows')?['value'], item()?['Id'])` in a Compose imports cleanly and fails every run
  with `InvalidTemplate`, "The template function 'select' is not defined or not valid". The same is true
  of `filter`, `map` and `reduce`. Use the `Select` and `Filter array` data operations instead. Their
  output is an array reached through `body('<action>')`.
- **`body()` and `outputs()` are not interchangeable, and which one is right follows from the action
  type.** `body('X')` is documented as shorthand for `actions('X').outputs.body`. A Compose holds its
  value directly in `outputs()` and has no body at all. A `Filter array`, a `Select`, a `Parse JSON` and
  every connector action wrap theirs, so those need `body()`. Get it wrong and the value still arrives,
  as the wrapper object rather than the array inside it, so the failure surfaces later and somewhere
  else: `union` reporting "expects parameters of same type, but found 'Array,Object'" is this mistake one
  action upstream. The designer's own `outputs('X')?['body/field']` is correct for either, because it
  navigates into the wrapper, so do not go correcting those.
