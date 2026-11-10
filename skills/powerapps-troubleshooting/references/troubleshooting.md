# Troubleshooting. Error to cause to fix

Every entry here happened on a real build. Search this page first, the exact message is usually listed. Deeper explanations live in the doc referenced per row.

---

## Nothing errors

An error index cannot help with these, because there is no error to look up. When the app
behaves wrongly and the Formulas panel is clean and the flow run history is green, start here.

| What you see | What is actually happening | Owning skill |
|---|---|---|
| After an import, a people picker's list shows blank rows before anyone types, typing a name finds nobody, and a saved person only shows once the dropdown is opened. Real users see it the moment the import lands | `SearchItems` holds the template sample `Search(ComboBoxSample, Self.SearchText, Value1)`. Source cannot carry `SearchItems` and search text in `Items` does not help. Restore it with `fix_picker_search.py`, or rebuild the picker as a non searchable combo fed by a text input | `powerapps-source-workflow` |
| A people picker or a `LookUp` over `Choices(List.PersonColumn)` never finds some people | Without search text `Choices` on a Person column returns only the first few dozen people. Pass the search text | `powerapps-powerfx` Rule 24 |
| A people picker list opens and lets you choose, but typing a name filters it to nothing | `SearchFields` reads `["Claims"]` (the raw login string) instead of `["DisplayName"]`, often after a copy paste in Studio. Studio flags nothing. Set it to `["DisplayName"]` in Advanced or in pa.yaml. Claims is only right on a deliberate email recipient picker | `powerapps-source-workflow` |
| A count or a gallery is confidently wrong, and gets wronger as the list grows | The filter cannot fold, so the app computed over the first 500 rows and stopped. No warning at runtime, only a blue underline at author time | `powerapps-sharepoint-data` |
| A `LookUp` default is always blank and the formula reads correctly | It targets a Choice value that does not exist on the live column. A missing choice returns blank, not an error. Compare the string against the live choice list first, "Finance" against a choice actually called "Finance Lead" | `powerapps-sharepoint-data` |
| A column the app writes comes back empty on every new row | The flow's Response action has an empty `body: {}`, so `.Run()` hands back blanks and the app patches those. Only the schema is validated, not the body. Read the Response body, not the app formula | `powerapps-approvals-and-flows` |
| The app acts on a value a flow has just changed as if the flow never ran, for example skipping an email | The flow wrote the row and the app's `LookUp` returned its cached copy. `Refresh` the list after the flow call, then `LookUp` | `powerapps-powerfx` Rule 27 |
| A date prints as the day before | A time off Date column stores midnight UTC, and `convertTimeZone` moves it into the previous evening | `powerapps-sharepoint-data` |
| Yes/No logic misbehaves on rows created before the column existed | Those rows read blank, and blank is not false | `powerapps-powerfx` |
| A whole expression evaluates to blank with no red anywhere | An untyped `Table()` default poisoned it. The type error surfaces nowhere | `powerapps-powerfx` |
| A saved green state vanishes after a refresh | It only ever lived in a variable. SharePoint never held it | `powerapps-architecture-and-ui` |
| A flow button fails for every normal user, the owner's clicks work in Studio and in the published app, and the flow's run history has no run at all for the failed clicks | The published app lost its hand-off to the flows for non-owners, so the call is rejected before a run exists. Seen after command-line imports of the app and its flows. Owners are never affected, so an owner's test passes and proves nothing | `powerapps-source-workflow` |
| `pac solution import` prints nothing and looks hung | Without `--async` the CLI is silent for the whole import. It is running. Use `--async --max-async-wait-time 8`, which streams progress. Do not fall back to the portal | `powerapps-source-workflow` |
| A connection reads Connected in the portal, and flows fail on it | The refresh token died months ago. The status does not track it | `powerapps-source-workflow` |
| The app packs fine and then misbehaves or will not load | Pack does not validate property names, YAML syntax, or Power Fx. A clean pack is not a clean app | `powerapps-source-workflow` |
| A rename in SharePoint breaks nothing, then breaks everything later | Display name renames do not change internal names, and formulas bind to internal names | `powerapps-sharepoint-data` |

## Build and toolchain

| Symptom | Cause | Fix | Owning skill |
|---|---|---|---|
| `'pac' is not recognized` | Fresh shell predates the CLI install's PATH change | Refresh PATH: `$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")`. Or install the CLI | `powerapps-source-workflow` |
| `Authentication required` from pac | Token expired | Re-run `pac auth create --environment https://<org>.crm.dynamics.com` | `powerapps-source-workflow` |
| `running scripts is disabled on this system` | PowerShell execution policy | `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` | `powerapps-source-workflow` |
| Studio will not load a packed app, `PA2108 Unknown property 'SearchItems' for Classic/ComboBox` | A `SearchItems` line was written into pa.yaml. Source cannot carry that property | Delete the line and repack. Ship as normal, then restore search in the published msapp with `fix_picker_search.py` (the shipping procedure), or use the two box picker that needs no fix | `powerapps-source-workflow` |
| Pack succeeds but the imported app is full of formula errors | Pack does not validate Power Fx | Load the msapp into a throwaway copy in Studio before a big ship, open the Formulas and errors panel after every import, and clear every red | `powerapps-source-workflow` |
| `PA1001 YamlInvalidSyntax` when Studio opens a packed app, or "This app couldn't be published" in the player | A plain scalar containing `: `, such as `Text: ="Status: open"` or a record literal. Pack accepts it | Write that property as a `\|-` block scalar and ship again | `powerapps-source-workflow` |
| `PA1001 YamlInvalidSyntax` pasting YAML into Studio | A `\|+` block scalar | Use `\|-` block scalars | `powerapps-source-workflow` |
| `PA2108 Unknown property 'AccessibleLabel' for Classic/Button`, or another property on another control | The property does not exist on that control family. Pack does not check property names | Delete it, or copy property names from an unpacked control of the same type | `powerapps-source-workflow` |
| `pac canvas download` fails with "Multiple canvas apps matching" | `--name` matches display names partially, and a second app's name contains this one ("TEST - Deal Review") | Pass the app id from `pac canvas list` to `--name`. In scripts, also check the file was written, not only the exit code | `powerapps-source-workflow` |
| `fix_picker_search.py` says the msapp still loads from YAML | The download is the source packed app. It has `packed.json` and stale `Controls/*.json` | Open the app in Studio for edit, Publish, download again | `powerapps-source-workflow` |
| The app has none of your changes after a ship where every step reported success | A Studio session was open during the import, so Studio kept the old app and the next publish shipped it. The clues are an import that finished in under a minute, your new control missing from the tree view, and the picker fix reporting `0 change(s)` | Close every Studio tab, import the same build again with a new version, and check the tree view before you publish | `powerapps-source-workflow` |
| `fix_picker_search.py` says `0 change(s)` and writes no file, right after a Studio publish | A publish resets every picker, so nothing to fix means the published app is not your build | Stop, do not import. See the row above | `powerapps-source-workflow` |
| Studio refuses to open the app with `PA1011`, "The keyword 'Layout' is required", though pack and import passed | A `Form` lost its control level `Layout: Vertical` key | Put the key back next to `Variant` and import again | `powerapps-source-workflow` |
| `fix_picker_search.py` prints a `MANUAL` line | That combo's `Items` is not a plain `Choices(<List>.<PersonColumn>)`, so its search cannot be derived | Write its `SearchItems` by hand in the msapp's `Controls/*.json`, or make `Items` a plain `Choices()` in source | `powerapps-source-workflow` |
| Play mode still shows the previous version after an import | The player cached the old version | Click the "You're using an old version, Refresh" banner | `powerapps-source-workflow` |
| Import shows a "validate by opening in Studio" banner | Normal for a YAML packed app | Open it in Studio once | `powerapps-source-workflow` |
| `git pull` rejected, remote contains work you do not have | Repo edited on GitHub directly | Run `git pull --rebase --autostash` on your branch before you push | `powerapps-source-workflow` |
| A PR shows a giant unreadable diff | Binary msapp in git, or a full re-unpack | Gitignore the msapp binaries. Expect re-indentation noise in YAML diffs, write commit messages that describe the app change | `powerapps-source-workflow` |

## Power Fx, at author time

| Symptom | Cause | Fix | Owning skill |
|---|---|---|---|
| `Name isn't valid. 'r' isn't recognized` on an inline table field, plus cascading errors | A `Switch` or `If` branch returns a bare `Table()` so the row type loses the column | Type the default: `Table({ r: "" })` with the same columns as the real branches | `powerapps-powerfx` Rule 11 |
| Field names will not resolve inside `Concat`, `LookUp`, `ForAll` over an inline table | Missing row alias | Use `As`: `Concat(tbl As s, s.field, ...)` | `powerapps-powerfx` Rule 12 |
| `The name 'Value' is not recognized` or `The name 'Text' is not recognized` on a text input | The formula reads the other family's property | Classic reads `.Text`, modern reads `.Value`. Check the control family in the YAML | `powerapps-powerfx` Rule 13 |
| A red error on an `IfError` whose two halves both look right | The fallback's type differs from the value's, for example `Patch` (a record) with a `Notify` (a boolean) fallback | End the value chain with `; true`, or give a fallback of the same type | `powerapps-powerfx` Rule 25 |
| A `Patch` inside `ForAll` is rejected because it writes the data source the `ForAll` reads | The loop reads and patches the same list | One batch `Patch(List, rows, ForAll(rows As r, {...}))` | `powerapps-powerfx` Rule 26 |
| `Circular dependency` on load, pointing at an HTML header | HtmlViewer references a control whose value depends back on the HtmlViewer | Compute the text in OnVisible into a variable, reference the variable | `powerapps-powerfx` Rule 16 |
| `The name 'varX' is not recognized` | Variable renamed or never set in OnStart | Set it in OnStart (full Set() line) or fix the reference. Keep a rename map when renaming | `powerapps-architecture-and-ui` |

## Power Fx, at run time

| Symptom | Cause | Fix | Owning skill |
|---|---|---|---|
| Generic `Network Error` on Patch | Raw string or number patched into a Choice or Lookup column | `{ Value: "..." }` for Choice, `{ Id: n, Value: "..." }` for Lookup, Person record for Person | `powerapps-powerfx` Rule 1 |
| `Incompatible Type` on Patch | Record variable initialized with `Blank()` | Initialize with `Defaults(List)` | `powerapps-powerfx` Rule 2 |
| `Invalid number of arguments: received 9, expected 7-8` on a flow `.Run` | The app cached an old flow signature | Studio, Power Automate pane, remove the flow, re-add it. Not a code bug | `powerapps-powerfx` Rule 19 |
| Flow call fails inside the app with no useful message | No error handling around `.Run` | Wrap in IfError with a toast, then check the flow run history in the portal | `powerapps-powerfx` Rule 20 |
| Second file upload sends the first file again, or `Duplicate File` error | `Reset()` used on the attachment control | `ResetForm()` on the parent form. `Reset()` only for the plain text inputs | `powerapps-powerfx` Rule 14 |
| Uploaded file row fails with `Invalid URL value` | Percent encoded long URL overflowed the 255 character Hyperlink column | In the flow, store `decodeUriComponent(first(split(url, '?')))` | `powerapps-approvals-and-flows` |
| Email folder link is dead for some clients | Client name contains `&` or an apostrophe and the link builder only replaced spaces | `EncodeUrlComponent()` app side, clean the name at save time | `powerapps-powerfx` Rule 21 |
| Notification email link opens the app but not the record | The play URL in the button is a placeholder, or the deep link handler is missing | Real play URL in the button, `Param("dealId")` handler in OnStart | `powerapps-architecture-and-ui` |
| Clicking the stepper HTML does nothing | HtmlViewer cannot fire Power Fx | Real controls: a gallery of buttons, or transparent rectangles over the HTML | `powerapps-powerfx` Rule 15 |

## State and data

| Symptom | Cause | Fix | Owning skill |
|---|---|---|---|
| UI shows stale values after a Patch | Local record variable not re-fetched | `Set(varDeal, LookUp(Deals, ID = varDeal.ID))` after every patch | `powerapps-powerfx` Rule 3 |
| Saved state (a green confirmation, a substep) vanishes on reload | State lived only in a variable | Persist to a column, rehydrate the variable in OnVisible | `powerapps-powerfx` Rule 5 |
| A previous cycle's approver shows up, or an old approval counts | Query or combo DefaultSelectedItems missing the cycle filter | Add `Review_Cycle = varDeal.Review_Cycle` to every step scoped query, including combo defaults | `powerapps-powerfx` Rule 8 |
| Yes/No logic misbehaves on old rows | Blank is not false | `Coalesce(field, false)` on every Yes/No read | `powerapps-powerfx` Rule 9 |
| Notification flag flips back and forth | App and flow both write the column | One writer per column. The app reads, the flow writes (or the reverse), never both | `powerapps-powerfx` Rule 6 |
| Refresh button does not surface new SharePoint rows | Gallery bound to a collection snapshot | Bind Items to the data source with inline filters, then `Refresh(source)` works | `powerapps-architecture-and-ui` |
| Two users overwrote each other's step move | Move button did not re-read before writing | Re-read the live record, compare, stop and refresh if it moved | `powerapps-architecture-and-ui` |
| Send button stays enabled after a successful send | Missing the unsent row count gate in DisplayMode | Add the `CountRows(... Notification_Sent <> true) > 0` gate | `powerapps-architecture-and-ui` |
| Send button permanently dead after a failed save | IfError catch did not reset the debounce gate | The catch must `Set(varSendNotification_Ready, true)` | `powerapps-powerfx` Rule 7 |
| `Network error when using Patch function: Conflicts exist with changes` | The app is writing against a record version that a background flow already bumped, most often a guard or notifier that stamps a column a minute after the user's own save | Patch the row you fetch at that moment: `Patch(List, LookUp(List, ID = varRec.ID), {...})`. Re-fetching after the patch does not help, the stamp lands later | `powerapps-powerfx` Rule 22 |
| Uploaded files arrive in SharePoint as 4 byte documents that will not open | The `file` input is not in the trigger's `required` list, so Power Apps never transmits it and the flow writes the string `null` | Add `"file"` to `required`, then move the file object to its schema position in every `.Run` call. Confirm by expanding the trigger in a flow run, a body with no `file` key proves it | `powerapps-approvals-and-flows` |
| `TriggerInputSchemaMismatch`, "Expected String but got Null", on a flow that takes a file | `contentBytes: ""` on a `format: byte` field serialises to null, and a required schema rejects it | Pass a token base64 value instead, `{ name: "Link.url", contentBytes: "IA==" }` | `powerapps-approvals-and-flows` |

## Studio and environment

| Symptom | Cause | Fix | Owning skill |
|---|---|---|---|
| Every themed control renders black or blank in Studio | OnStart has not run this session | Tree view, App, Run OnStart. Required after any OnStart edit | `powerapps-architecture-and-ui` |
| `You don't have permission to do this` on Save | Missing Contribute on the SharePoint list | Fix SharePoint permissions, the app code is fine | `powerapps-approvals-and-flows` |
| A user cannot see a record in the browse view | Not on the record in any role, not an admin | Expected. Check the relevance gate | `powerapps-approvals-and-flows` |
| Admin cannot edit a step | By design, visibility is not authority | If truly needed, add the admin flag to that specific gate deliberately | `powerapps-approvals-and-flows` |
| Flow runs green but the folder or row is missing | Wrong site URL or list GUID in the action | Actions reference lists by GUID. Verify against the schema doc | `powerapps-approvals-and-flows` |
| Folder creation flow fails on re-run | `CreateNewFolder` errors when the folder exists | `runAfter` accepting Succeeded and Failed, plus the idempotency flag | `powerapps-approvals-and-flows` |
| Choice value patch silently does nothing or errors | The value drifted from what SharePoint actually has | Confirm current Choice values in SharePoint settings before coding against them | `powerapps-sharepoint-data` |
| `WorkflowOperationParametersExtraParameter`, "no definition for parameter 'overwrite'", on trying to turn a flow on | The SharePoint `CreateFile` action retired the `overwrite` parameter | Delete `overwrite` from the action's parameters. A same name upload still replaces the file, as a new version | `powerapps-approvals-and-flows` |
| An index file or list a flow maintains loses entries or shows only the latest | "Create file" with an existing name overwrites the file as a new version, it does not add one | Upsert the index (read, merge, write), never append by creating a file of the same name | `powerapps-approvals-and-flows` |
| `InvalidTemplate`, `createArray` "invoked with no parameters" | `createArray()` called with zero arguments in a flow expression | `createArray()` needs at least one item. Seed with `createArray('')` and filter blanks from the result | `powerapps-approvals-and-flows` |
| A control will not drop into a gallery when dragged in the tree view | Tree view drag and drop onto a gallery template is unreliable, it lands as a sibling or refuses outright | Select the gallery's template on the canvas first, then Insert the control. It lands inside the template | `powerapps-architecture-and-ui` |
| Red errors on a button nobody edited, right after re-adding an unrelated flow | The app cached the old signature of a flow whose Response outputs changed, and the re-add refreshed it to the real one | Read that flow's Response action body first. Then remove and re-add the flow in the Power Automate pane | `powerapps-powerfx` Rule 19 |
| A button that calls a flow fails for normal users only. The same click works for the app owner and for the service account, in Studio and in the published app. The failed clicks leave no run in the flow's history, and the button can show its success toast and its error toast together | After command-line imports of the app and its flows, the published app no longer hands a non-owner's call to the flow, so it is rejected before the flow starts. A plain Save and Publish in Studio does not repair it. Which import causes it, the app or the flows, is not yet known | In Studio, remove every flow in the Power Automate pane, add each one back under the same name (no `_1` suffix), confirm zero red in the Formulas panel, then Save and Publish. Have a non-owner reload the app and click once. Read who triggered a run by expanding the trigger's raw outputs, `x-ms-user-name` and `x-ms-user-agent` (`Web Player` is the published app, `Web AuthoringTool` is Studio) | `powerapps-source-workflow` |
| A solution import reports success but nothing changed | The solution `<Version>` was not bumped before rezipping (`solution.xml` at the zip root, `Other/Solution.xml` once unpacked) | Bump the version by hand, rezip, import again. Without the bump the import is accepted and applies nothing | `powerapps-approvals-and-flows` |
| Solution import fails with a `WriteAccess` error naming a connection reference | The reference record belongs to another user, and the importing account cannot write it | Delete the orphaned reference first, or give this solution its own references. Leave any reference shared with another app alone | `powerapps-source-workflow` |
| Flows will not turn on after an import, `Permission denied due to missing connection ACL` | A dead connection was repaired with Reconnect, which leaves the permission list broken | Create a new connection, repoint the connection reference at it, then turn the flows on | `powerapps-source-workflow` |
| Deleting a solution leaves the app and flows still running | Deleting an unmanaged solution removes only the solution record | In the solution's Objects view select all, Remove, Delete from this environment, then `pac solution delete`. Reimporting after deleting only the solution updates the same components instead of recreating them | `powerapps-source-workflow` |
| Deep links in emails and buttons open the wrong place after a rebuild | A recreated canvas app gets a new app id, flows keep their GUID | Grep the app source for the old app id before rebuilding, then repoint every link. Flow bindings need no work | `powerapps-source-workflow` |
| A flow is live that was meant to stay off | Solution import activates flows regardless of their exported state | Check every flow's state after an import, not just the ones you changed | `powerapps-source-workflow` |
| Import prints "The original workflow definition has been deactivated and replaced" | A note from the import about the replaced definition. The flows were still on afterwards | Check every flow's state anyway | `powerapps-source-workflow` |
| Studio Publish only saves, no publish dialog appears (often when driven from a browser tool) | The dialog can arrive late or not at all | Maker portal, the app, Versions, the newest version, Publish this version | `powerapps-source-workflow` |
| Studio stops responding when driven from a browser tool | An emulated viewport (1600 by 1000 here) | Use the browser's own desktop viewport | `powerapps-source-workflow` |

## When something is not listed

1. Read the exact error in the Formulas panel or the flow run history. The message is usually literal.
2. Check it against the rules in the `powerapps-powerfx` skill, most runtime surprises are already listed there.
3. Reproduce it in isolation (one button, one patch).
4. When it is new and real, fix it, then add the row here. That is how this table got built.
