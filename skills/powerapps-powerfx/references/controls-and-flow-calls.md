# Power Fx rules for controls, flow calls, and URLs

The second half of the numbered rules: controls, calling flows from the app, and URLs. Same format as `references/powerfx-rules.md`, wrong versus right, cite by number.

---

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

### Rule 18: `.Run()` arguments follow the trigger schema's order, and every input is required

Inputs appear in the flow JSON as `text`, `text_1`, `text_2`, `number`, `file`. The app passes them positionally in the order of the schema's `properties`. Mark every input required, the file too, or Power Apps may never send it. Full anatomy in the `powerapps-approvals-and-flows` skill.

### Rule 19: "received 9, expected 7-8" is a cache, not your code

The app stored an old copy of the flow's signature. Studio: Power Automate pane, remove the flow, re-add it. Then the argument count matches. Any time a flow's inputs change, every app using it needs this refresh.

The cache holds the outputs too, not just the inputs, and that version is much harder to recognise. Change what a flow's Response action returns and the app keeps compiling against output names that no longer exist, so red errors appear on a button nobody edited, often right after some unrelated flow was re-added and quietly refreshed the signature. Same fix, remove and re-add. The diagnostic order is what matters: when a formula that calls a flow suddenly errors, read the flow's Response action body before changing one character of the formula.

### Rule 20: Wrap flow calls, then re-fetch

```
IfError(
    With({ result: CreateFolder.Run(varDeal.Customer, varDeal.Deal_Reference,
                                    varDeal.Route.Value, Text(varDeal.ID)) },
        Patch(Deals, LookUp(Deals, ID = varDeal.ID),
            { Folders_Created: true, Folder_Link: result.folderpath })
    );
    Set(varDeal, LookUp(Deals, ID = varDeal.ID));
    Notify("Folder created.", NotificationType.Success),
    Notify("Could not create the folder. Check the flow run history.", NotificationType.Error)
)
```

`With` captures the flow's response record so the returned fields can be used in the same expression. Here the app writes the returned values itself, so the re-fetch after its own Patch is enough. When the flow writes the row, Rule 27 applies.

### Rule 27: After a flow writes a row, `Refresh` before you `LookUp`

```
// WRONG: the flow flagged the approval rows, the count reads the app's cached copy
NotifyApprovers.Run(varDeal.ID, varAppLink); If(CountRows(Filter(Approvals, ... )) = 0, NotifyPM.Run(...))

// RIGHT, with the full unsent count (Rules 8 and 9): refresh the list the flow wrote (Deals for a flow that writes the record)
NotifyApprovers.Run(varDeal.ID, varAppLink);
Refresh(Approvals);
If(CountRows(Filter(Approvals, Deal.Id = varDeal.ID && Step_Number.Value = "7"
        && Review_Cycle = varDeal.Review_Cycle && Coalesce(Notification_Sent, false) <> true)) = 0,
    NotifyPM.Run(varDeal.ID, varAppLink))
```

The app's own Patch updates its cache, a flow's write does not. A read straight after the flow returns the rows as they were before it ran. The call only waits for the flow when the flow ends in a Respond to a Power App or flow action, so give it one. On one build that stale read decided whether to send the next email, and the email was skipped with nothing in red.

## URLs

### Rule 21: Encode anything user named that goes into a URL

```
// WRONG: breaks on spaces and special characters
Launch(".../Shared Documents/" & varDeal.Customer & ...)

// RIGHT
Launch(".../Shared%20Documents/" & EncodeUrlComponent(varDeal.Customer) & ...)
```

Client names contain spaces, ampersands and apostrophes. Flow side string building that only replaces spaces with %20 will still break on `&` and `'`, so treat cleanup of those characters as part of saving the name.
