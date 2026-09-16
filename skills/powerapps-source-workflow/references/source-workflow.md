# Canvas source workflow. pa.yaml, packing, and shipping from source

How a canvas app becomes text you can edit, how it gets back into the cloud with its AppId intact, and the one property source cannot carry.

---

## What pack can and cannot do

`pac canvas pack` and `unpack` are a deprecated preview feature. Microsoft's own docs say the generated `.pa.yaml` is read only, for reviewing changes, and the supported source control path (Power Platform Git Integration) requires Dataverse.

In practice the whole app round trips. `pac canvas pack --sources <src> --msapp app.msapp` packs apps that contain `Classic/ComboBox` people pickers and the attachment form stack (`Form` plus `TypedDataCard` variant ClassicAttachmentsEdit plus `Attachments`). Every formula survives a source ship except one.

The combo's `SearchItems` property cannot live in source:

- Unpack omits it.
- If you add it to pa.yaml, Studio's YAML loader rejects the app with `PA2108 Unknown property 'SearchItems' for Classic/ComboBox`.
- Studio's Advanced pane does not expose it.
- `Items: Choices(Deals.Sales_Owner, Self.SearchText)` does not give search either.

So never try to fix picker search in YAML or in Studio. It is restored after the ship, in the published msapp, by `scripts/fix_picker_search.py` in this skill (see Shipping from source below).

Two msapp states matter for that fix:

- A source packed msapp contains `packed.json` with `LoadFromYaml` true. The app loads from `Src/*.pa.yaml` and the `Controls/*.json` inside it are stale.
- Once the app has been opened in Studio and published, a downloaded msapp has no `packed.json` and `Controls/*.json` is authoritative. That is the file the script edits.

## The source tree

`pac canvas unpack --layout SourceCode` produces:

```
app/
  src/
    <AppName>.msapr          binary sidecar (connections, datasources, control templates). Keep in git.
    Src/
      App.pa.yaml            App.OnStart, theme
      scr_<Screen>.pa.yaml   one file per screen. The UI lives here.
      _EditorState.pa.yaml   Studio cache
```

Only `Src/*.pa.yaml` are meant for review and editing. The packed `.msapp` is a build output, gitignore it. A single screen app has essentially one big file (a production main screen runs 200 to 500 KB of YAML), so search by control name, not by scrolling.

## pa.yaml anatomy

YAML with `=` prefixed Power Fx expressions. A control looks like this:

```yaml
Screens:
  scr_Main:
    Properties:
      Fill: =varTheme.Light
    Children:
      - con_App:
          Control: GroupContainer@1.5.0
          Variant: ManualLayout
          Properties:
            Height: =Parent.Height
            Width: =Parent.Width
          Children:
            - lbl_Title:
                Control: Label@2.5.1
                Properties:
                  Text: ="Hello"
                  X: =24
                  Y: =14
```

Rules that matter:

- Indentation is load bearing. A top level container child sits at 12 spaces (`            - con_X:`), its `Control`, `Properties` and `Children` keys at 16, its child controls at 18, their properties at 24. Moving a control between nesting levels re-indents every line under it. Treat a move as a rewrite, not a shuffle.
- Multi line formulas use a `|-` block scalar under the property, each line prefixed by the deeper indent.
- A formula containing `: ` (colon space, as in a record literal `{ Value: "Open" }`) must be a `|-` block scalar, even on one line. Inline it reads as a YAML mapping.
- When pasting YAML into Studio, use `|-` block scalars, never `|+`. Studio rejects `|+` with `PA1001 YamlInvalidSyntax`.
- Control declarations carry a version: `Label@2.5.1`, `Classic/Button@2.2.0`. Copy versions from controls that already exist in the app.
- Containers used are plain `GroupContainer@1.5.0` with `Variant: ManualLayout`, positioned by X and Y. No auto layout containers. Manual positioning is more YAML but it packs and behaves predictably.

Common control set that packs cleanly: `GroupContainer@1.5.0`, `Label@2.5.1`, `Classic/Button@2.2.0`, `Classic/TextInput@2.3.2`, `Classic/CheckBox@2.1.0`, `Classic/DatePicker@2.6.0`, `Classic/ComboBox@2.4.0`, `Gallery@2.15.0` (Variant Vertical or Horizontal), `HtmlViewer@2.1.0`, `Timer`, `Icon`, `Rectangle`, and the attachment form stack.

A people picker in source. No `SearchItems` line, ever:

```yaml
            - cmb_S1_SalesOwner:
                Control: Classic/ComboBox@2.4.0
                Properties:
                  Items: =Choices(Deals.Sales_Owner)
                  DisplayFields: =["DisplayName"]
                  SearchFields: =["DisplayName"]
                  SelectMultiple: =false
                  DefaultSelectedItems: |-
                    =If(IsBlank(varDeal.Sales_Owner), [], Table(varDeal.Sales_Owner))
                  X: =24
                  Y: =60
                  Width: =300
```

Keep `Items` a plain `Choices(<List>.<PersonColumn>)`. The fix script derives search from it, and any other shape is left for a human. The Save button writes the person with `Sales_Owner: cmb_S1_SalesOwner.Selected`, and a picker that pre-fills from an approvals row carries the cycle filter in its `DefaultSelectedItems` LookUp (the `powerapps-powerfx` skill, Rule 8). Write one picker, then copy its YAML and change the name and the column.

The attachment form stack (`frm_Docs_Upload` holding `dc_Docs_Attachments` holding `att_Docs_Files`) has too many generated properties to write from nothing. Copy its YAML from an unpacked app that has one, or insert a form bound to the file index list in Studio once, keep only the attachments card, and pull the app into source. From then on it is source like everything else. The upload wiring is in the `powerapps-approvals-and-flows` skill.

## The dev loop

Ship a helper script (`powerapps/app/app.ps1`) with two verbs:

- `pack`: `pac canvas pack --msapp <App>_built.msapp --sources src --layout SourceCode`, then print the path.
- `pull`: `pac canvas download` plus `pac canvas unpack`, guarded behind a `-Force` flag with a loud warning, because pull overwrites `src/` with the cloud copy.

The loop:

1. Edit `src/Src/scr_*.pa.yaml`.
2. `app.ps1 pack`.
3. Load the build into a throwaway copy with Import app from file, and never Save it. A YAML packed app shows a one time "validate by opening in Studio" banner. Expected.
4. Run App.OnStart once (Tree view, App, three dots, Run OnStart) so variables exist.
5. Open the Formulas and errors panel and clear every red error.
6. Fix in YAML, repack, repeat. When it is clean, ship it with the procedure below.

The critical mindset: pack success is not correctness. Pack does not validate property names, YAML syntax, or Power Fx. A misspelled property or a broken block scalar packs fine and fails only when Studio loads the app. Loading the msapp in Studio is the real check, so do it before every big ship.

On first ever load the data connections must be added once inside Studio (add the SharePoint lists as data sources). After that, the app keeps them.

## Shipping from source

The canonical procedure. It updates the existing app in place, so the AppId, the play URL, and every deep link stay the same. Run the fix script by its path inside this skill folder. It needs Python 3 and nothing else.

1. The app lives alone in an app-only solution. Flows live in their own solution, so an app import never touches a flow (see Solutions below).
2. Start from source pulled from the live app (`pac canvas download`, then `pac canvas unpack --layout SourceCode`) unless the repo is already current. Edit `Src/*.pa.yaml`, then `pac canvas pack --sources <src> --msapp build.msapp`.
3. `pac solution export --name <AppSolution> --path app.zip`. Unzip it. Replace `CanvasApps/<name>_DocumentUri.msapp` with `build.msapp`. Bump `<Version>` in `solution.xml` at the zip root. Zip the folder contents (not the folder itself) back to `app.zip`, then import:
   ```
   pac solution import --path app.zip --async --max-async-wait-time 15 --publish-changes --force-overwrite
   ```
   Without the version bump the import reports success and applies nothing.
4. People pickers now have no working search. Open the app in Studio for edit and Publish. Nothing to paste or rebuild, the publish is the whole step.
5. Download the published app and fix it:
   ```
   pac canvas download --name "<App name>" --file-name live.msapp
   python scripts/fix_picker_search.py live.msapp fixed.msapp
   ```
   If the script says the msapp still loads from YAML, step 4 did not happen.
6. Swap `fixed.msapp` into the solution exactly as in step 3, bump `<Version>` again, and import.
7. Verify. Download again (add `--overwrite`) and run `python scripts/fix_picker_search.py live.msapp` with no output file. Expect `0 change(s), 0 manual`. Then type a name into one picker in Play mode. A player still showing the old version needs the "You're using an old version, Refresh" banner clicked.

An app with no people pickers stops after step 3.

What the script does, per `Classic/ComboBox` in `Controls/*.json`:

- Reads the combo's own `Items: Choices(<List>.<PersonColumn>)` and writes `SearchItems: Choices(<List>.<PersonColumn>,<comboName>.SearchText)`. After a Studio publish every picker holds the template sample `Search(ComboBoxSample, Self.SearchText, Value1)`, which is why typing a name finds nobody and a saved person only shows after the dropdown is opened.
- Leaves `SearchFields` alone. A picker that opens but filters to nothing as you type is searching `["Claims"]`, see the `powerapps-troubleshooting` skill.
- Reports a combo whose `Items` is not a plain `Choices(List.Column)` as `MANUAL`. Those need their `SearchItems` written by hand into the same JSON.
- Without an output file it only reports. Exit code 0 means nothing to fix, 1 means changes or manual items, 2 means the msapp still loads from YAML.

Notes:

- Pickers are broken from step 3 until step 6 lands, a matter of minutes. On an app people are using, run steps 3 to 6 back to back in a quiet window.
- Studio edits made after a ship live only in the cloud. Run `app.ps1 pull -Force` and commit before the next source edit, or the next ship overwrites them. The pull brings no `SearchItems` into source, which is correct.

## Small edits in Studio

For a handful of formula changes, pasting into Studio is still the fastest path:

1. The developer (or the AI assistant, see the `powerapps-build-playbook` skill) writes the exact property values, stated as "control X, property Y, paste this".
2. A human pastes them into Studio, tests, publishes.
3. Pull the app into the repo (`app.ps1 pull -Force` on a branch), commit, open a pull request.

Nothing unconfirmed lands in git, and the repo is back in step with the cloud before anyone edits source again. Run the fix script in report mode on the downloaded msapp while you have it. It settles whether picker search is still intact.

For larger work, a restyle, a new panel, a batch of pickers, edit source and ship.

## Solutions: two containers

Even without Dataverse tables, the app and the flows live in Dataverse solutions, because that is the unit Power Automate exports and imports. Keep two:

- An app-only solution holding the canvas app and nothing else. This is what the ship procedure exports and imports.
- A flow solution holding the flows and their connection references.

Create the app-only solution once in the maker portal: Solutions, New solution, then Add existing, App, Canvas app. An app import can then never overwrite or reactivate a flow, and a flow edit cycle never drags a large msapp through export and import. Adding the app to a solution does not change the app or its AppId.

The unpacked flow solution layout:

```
powerapps/flows/<SolutionName>/
  Other/
    Solution.xml            manifest: solution name, version, publisher, root components
    Customizations.xml
  Workflows/
    <FlowName>-<GUID>.json           the flow definition (the code)
    <FlowName>-<GUID>.json.data.xml  sidecar: name, type, state
```

The app solution has the same `Other/` plus `CanvasApps/<prefix>_<appname>_<hash>.meta.xml` and `CanvasApps/<prefix>_<appname>_<hash>_DocumentUri.msapp`. Gitignore that binary. The source is `Src/*.pa.yaml`.

## What survives a delete and reimport, and what does not

Sooner or later something has to be rebuilt: a new owner, a botched import, a move. Four facts decide whether that is an afternoon or a week.

Deleting a solution deletes the container, not the contents. The app and every flow stay in the environment, still running, now sitting in the default solution. Deleting the solution and importing a fresh copy therefore updates the same components rather than recreating them, which is exactly what you do not want if the point was to recreate them. Delete the components explicitly first.

Flows keep their GUID, the canvas app does not. `Customizations.xml` pins each flow as `<Workflow WorkflowId="{...}" Name="...">`, and import recreates the workflow record with that same id. Since a canvas app references its flows by id, the app's wiring survives a delete and reimport untouched, with no re-adding in the Power Automate pane. A canvas app gets a new app id, so its play URL changes, and every deep link built from it breaks. Grep the app source for the old id before you start, so you know how many buttons to repoint. A normal ship is an update, not a delete, and keeps the id.

Connection references belong to whoever created them, and an import that touches one it does not own fails with a `WriteAccess` error naming a connection reference record. This is what stops a second account importing a solution built by the first. Delete the orphaned references first, or have the new owner import a solution whose references it can create fresh. Where a reference is shared with another app, leave it alone and give this solution its own instead.

Import activates flows. A flow exported in a draft state comes back on, so a change you meant to stage lands live. Check the state of every flow after an import and turn back off anything that was meant to stay off.

## Ownership: put the app under a service account

An app owned by a person is a dependency on that person. When they change roles the flows stop, the emails stop, and nobody else can edit it. The pattern that holds: a service account owns the app and the flows, a security group of the developers is co-owner on both, and the flows run on the service account's connections so outgoing mail comes from the service rather than a person.

Do it on day one. Retrofitting is a migration.

The mechanics are two different jobs, and neither is self service.

- Canvas app: `Set-AdminPowerAppOwner` from `Microsoft.PowerApps.Administration.PowerShell`, which needs a Power Platform admin. Re-share the previous owner as co-owner straight afterwards, otherwise they lose the access that `pac canvas download` depends on.
- Solution aware flows: these are Dataverse records, so `Set-AdminFlowOwnerRole` does not apply. An administrator reassigns them in the Dataverse Processes list.

Ownership and runtime identity are separate. Changing the owner moves a field and nothing else. The flows keep running on the old owner's connections until someone signs in as the service account and repoints each connection reference, and that is the step that actually gets a personal name off the emails.

Solution aware flows have no "Run only users" panel, so do not go looking for one. Users of the app get run access through the app's own sharing.

## Verification checklist after any import

1. Open the app in Studio.
2. Run App.OnStart once. Without it every `var` is blank and the theme renders as black boxes.
3. Formulas and errors panel: zero red.
4. Click through the changed feature against real SharePoint data.
5. Type a name into a people picker. If it finds nobody, finish the ship procedure from step 4.
6. If a flow signature changed, remove and re-add the flow in the Power Automate pane (see the `powerapps-troubleshooting` skill, "received 9, expected 7-8").
7. Every flow in the expected state, on or off, and connection references pointing at the right connections.

## What belongs in git

| Item | In git? |
|---|---|
| `Src/*.pa.yaml` | Yes. This is the source. |
| `<App>.msapr` sidecar | Yes. Pack needs it. |
| Packed or downloaded `.msapp` | No. Build artifact. |
| Unpacked solutions (Other/, Workflows/) | Yes. |
| Canvas binary inside the solution unpack | No. |
| `SCHEMA_AS_BUILT.md`, `STUDIO_TODO.md` | Yes. They are the contract and the manual log. |
