# Canvas source workflow. pa.yaml, packing, and shipping from source

How a canvas app becomes text you can edit, how it gets back into the cloud with its AppId intact, and the one property source cannot carry.

---

## What pack can and cannot do

`pac canvas pack` and `unpack` are a deprecated preview feature. The pac reference page says so and points at Power Platform Git Integration, which needs Managed Environments (premium). Microsoft's docs also still call the generated `.pa.yaml` read only, though pac 2.7 (May 2026) added the `SourceCode` layout this skill uses and the canvas authoring MCP pushes pa.yaml into Studio (below). No removal date has been announced. Use `--layout SourceCode` explicitly, because the default is still the deprecated Experimental layout.

In practice the whole app round trips. `pac canvas pack --sources <src> --msapp app.msapp` packs apps that contain `Classic/ComboBox` people pickers and the attachment form stack (`Form` plus `TypedDataCard` variant ClassicAttachmentsEdit plus `Attachments`). Every formula survives a source ship except one.

The combo's `SearchItems` property cannot live in source:

- Unpack omits it.
- If you add it to pa.yaml, Studio's YAML loader rejects the app with `PA2108 Unknown property 'SearchItems' for Classic/ComboBox`.
- Studio's Advanced pane does not expose it.
- Whatever compiles the YAML, Studio or the player, gives every searchable combo the template sample `Search(ComboBoxSample, Self.SearchText, Value1)`. The dropdown shows blank rows even before anyone types, and typing finds nobody.
- Putting the search text into `Items` does not help, as `Choices(Deals.Sales_Owner, Self.SearchText)` or with the combo's own name. The template `SearchItems` still wins.
- The `.msapr` sidecar holds the last Studio compiled `Controls/*.json`, the correct `SearchItems` included. Studio and the player rebuild from the YAML and drop it.

The canvas authoring MCP has the same problem. Microsoft confirmed on the power-platform-skills repo that the designer sets a hidden `SearchItems` that `compile_canvas` does not trigger, and open issues there report searchable Classic combos going blank after a compile, reaching production through a managed solution.

So never try to fix picker search in YAML or in Studio. Pick one of two proven ways out:

- Patch it after the ship. `scripts/fix_picker_search.py` in this skill rewrites `SearchItems` in the published msapp (Shipping from source below). One combo per picker, looks like any picker, costs a second import on every ship.
- Do not make the combo searchable. Set `IsSearchable: =false` on the combo and put a classic text input next to it, with the combo's `Items: =Choices(Deals.Sales_Owner, txt_S1_OwnerSearch.Text)`. The text input does the search over the whole directory, the combo shows and selects the person, and it ships from source with no patch. The cost is a second box per picker, which some teams turn down for looks.

Microsoft's own suggestion is the modern combo box (`ModernCombobox`), which has no `SearchItems` or `SearchFields` at all. Its docs say nothing about SharePoint person columns or directory search, and it is not proven on this stack. Test it on one picker before building around it.

Two msapp states matter for the patch:

- A source packed msapp contains `packed.json` with `LoadFromYaml` true. The app loads from `Src/*.pa.yaml` and the `Controls/*.json` inside it are stale.
- Once the app has been opened in Studio and published, a downloaded msapp has no `packed.json` and `Controls/*.json` is authoritative. That is the file the script edits.

A packed app imported in a solution plays for users straight away. Nobody has to open Studio first. So from the first import until the patched import lands, every searchable people picker is broken for real users.

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
- A formula containing `: ` (colon space) must be a `|-` block scalar, even on one line. That covers a record literal `{ Value: "Open" }` and a plain string such as `Text: ="Status: open"`. Inline it reads as a YAML mapping. Pack accepts it, Studio refuses to open the app with `PA1001 YamlInvalidSyntax`, and the player shows "This app couldn't be published".
- When pasting YAML into Studio, use `|-` block scalars, never `|+`. Studio rejects `|+` with `PA1001 YamlInvalidSyntax`.
- A formula with trailing spaces on any line unpacks as one double quoted line with `\n` written out, not as a block scalar. A script that edits formulas line by line finds nothing there, so make it assert every match and handle that form too.
- A `Form` needs the control level key `Layout: Vertical` next to `Variant`. It is not a property, so a generator that writes only Control, Variant and Properties drops it. Pack and the import both pass, then Studio refuses to open the whole app with `PA1011`.
- `AddColumns` wants the new column name as a bare identifier (`AddColumns(T, DispStatus, ...)`), even in an msapp that says `powerfxv1: false`. `SortByColumns(T, "Name", ...)` with a string still works.
- Control declarations carry a version: `Label@2.5.1`, `Classic/Button@2.2.0`. Copy versions from controls that already exist in the app.
- Not every property a control has in one family exists in another. `Classic/Button` rejects `AccessibleLabel` with `PA2108` when Studio opens the app, though pack accepts it. Copy property names from an unpacked control of the same type, not from memory.
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

Keep `Items` a plain `Choices(<List>.<PersonColumn>)`. The fix script derives search from it, and any other shape is left for a human. Without search text, `Choices` on a Person column returns only the first few dozen people of the directory, so the open list is a sample, not everyone (the `powerapps-powerfx` skill, Rule 24).

The same picker without the patch, a non searchable combo fed by a text input:

```yaml
            - txt_S1_OwnerSearch:
                Control: Classic/TextInput@2.3.2
                Properties:
                  HintText: ="Type a name"
                  X: =24
                  Y: =60
            - cmb_S1_SalesOwner:
                Control: Classic/ComboBox@2.4.0
                Properties:
                  Items: =Choices(Deals.Sales_Owner, txt_S1_OwnerSearch.Text)
                  IsSearchable: =false
                  DisplayFields: =["DisplayName"]
                  SelectMultiple: =false
                  X: =24
                  Y: =100
```

The fix script skips a combo whose `IsSearchable` is false, so this picker never needs the second import. The Save button writes the person with `Sales_Owner: cmb_S1_SalesOwner.Selected`, and a picker that pre-fills from an approvals row carries the cycle filter in its `DefaultSelectedItems` LookUp (the `powerapps-powerfx` skill, Rule 8). Write one picker, then copy its YAML and change the name and the column.

The attachment form stack (`frm_Docs_Upload` holding `dc_Docs_Attachments` holding `att_Docs_Files`) has too many generated properties to write from nothing. Copy its YAML from an unpacked app that has one, or insert a form bound to the file index list in Studio once, keep only the attachments card, and pull the app into source. From then on it is source like everything else. The upload wiring is in the `powerapps-approvals-and-flows` skill.

## The dev loop

Keep a small helper script in the app repo (`powerapps/app/app.ps1`). You write it, it is not part of this skill. Two verbs:

- `pack`: `pac canvas pack --msapp <App>_built.msapp --sources src --layout SourceCode`, then print the path.
- `pull`: `pac canvas download --name <AppId>` plus `pac canvas unpack`, guarded behind a `-Force` flag with a loud warning, because pull overwrites `src/` with the cloud copy.

The loop:

1. Edit `src/Src/scr_*.pa.yaml`.
2. `app.ps1 pack`, with the colon check below as its first step.
3. Load the build into a throwaway copy with Import app from file, and never Save it. A YAML packed app shows a one time "validate by opening in Studio" banner. Expected.
4. Run App.OnStart once (Tree view, App, three dots, Run OnStart) so variables exist.
5. Open the Formulas and errors panel and clear every red error.
6. Fix in YAML, repack, repeat. When it is clean, ship it with the procedure below.

The critical mindset: pack success is not correctness. Pack does not validate property names, YAML syntax, or Power Fx. A misspelled property or a broken block scalar packs fine and fails only when Studio loads the app. `pac canvas validate` was deprecated in pac 2.6 (April 2026). It still appears in `pac canvas` help, but on pac 2.7.4 it answers "'pac canvas validate' is no longer supported". Loading the msapp in Studio is the real check, so do it before every big ship.

One YAML trap is cheap to catch before packing. A plain scalar holding `: ` passes pack and breaks the app (the anatomy rules above). This finds every one, and should print nothing:

```powershell
Select-String -Path src\Src\*.pa.yaml -Pattern '^\s+[\w.]+: =.*: '
```

On first ever load the data connections must be added once inside Studio (add the SharePoint lists as data sources). After that, the app keeps them.

## Shipping from source

The canonical procedure. It updates the existing app in place, so the AppId, the play URL, and every deep link stay the same. Run the fix script by its path inside this skill folder. It needs Python 3 and nothing else.

1. The app lives alone in an app-only solution. Flows live in their own solution, so an app import never touches a flow (see Solutions below).
2. Start from source pulled from the live app (`pac canvas download`, then `pac canvas unpack --layout SourceCode`) unless the repo is already current. Edit `Src/*.pa.yaml`, then `pac canvas pack --sources <src> --msapp build.msapp --layout SourceCode`.
3. Close every Studio tab of the app, yours and anyone else's. Then `pac solution export --name <AppSolution> --path app.zip`. Unzip it. Replace `CanvasApps/<name>_DocumentUri.msapp` with `build.msapp`. Bump `<Version>` in `solution.xml` at the zip root. Zip the folder contents (not the folder itself) back to `app.zip` (`Compress-Archive -Path .\app\* -DestinationPath app.zip -Force`), then import:
   ```
   pac solution import --path app.zip --async --max-async-wait-time 15 --publish-changes --force-overwrite
   ```
   Without the version bump the import reports success and applies nothing.
4. The app is live for users now, and searchable people pickers have no working search. Do not pause here. Open the app in Studio for edit and confirm that a control you added is in the tree view, which proves your build loaded. Then Publish. If Studio shows nothing to save, change a property and change it back (typed, not Undo) first, because a publish with no edit does not save a new copy. If the publish dialog never appears and Studio only saves, publish that saved version from the maker portal instead: the app's Versions page, the new version, Publish this version.
5. Download the published app and fix it. Pass the app id, not the display name, and check the file exists, not only the exit code:
   ```
   pac canvas download --name <AppId> --file-name live.msapp --overwrite
   python scripts/fix_picker_search.py live.msapp fixed.msapp
   ```
   `--name` matches partial display names, so a second app whose name contains this one ("TEST - Deal Review" next to "Deal Review") fails the download with "Multiple canvas apps matching". `pac canvas list` shows the id. If the script says the msapp still loads from YAML, step 4 did not happen. Expect one change per picker, because a Studio publish resets them all. `0 change(s)` here means the publish did not contain your build, so stop and do not import. The script writes no output file in that case.
6. Swap `fixed.msapp` into the solution exactly as in step 3, bump `<Version>` again, and import.
7. Verify. Download again (add `--overwrite`) and run `python scripts/fix_picker_search.py live.msapp` with no output file. Expect `0 change(s), 0 manual`. Then type a name into one picker in Play mode. A player still showing the old version needs the "You're using an old version, Refresh" banner clicked.

An app with no searchable people pickers (none at all, or only the two box kind) stops after step 3.

What the script does, per `Classic/ComboBox` in `Controls/*.json`:

- Reads the combo's own `Items: Choices(<List>.<PersonColumn>)` and writes `SearchItems: Choices(<List>.<PersonColumn>,<comboName>.SearchText)`. After a Studio publish every picker holds the template sample `Search(ComboBoxSample, Self.SearchText, Value1)`, which is why typing a name finds nobody and a saved person only shows after the dropdown is opened.
- Leaves `SearchFields` alone. A picker that opens but filters to nothing as you type is searching `["Claims"]`, see the `powerapps-troubleshooting` skill.
- Skips a combo with `IsSearchable` false.
- Reports a searchable combo whose `Items` is not a plain `Choices(List.Column)` as `MANUAL`. Those need their `SearchItems` written by hand into the same JSON.
- Without an output file it only reports. Exit code 0 means nothing to fix, 1 means changes or manual items, 2 means the msapp still loads from YAML.

Notes:

- An open Studio session can swallow a ship with every step reporting success. A Studio tab stayed open during an import. The import finished in under a minute instead of minutes, Studio then opened the old app, and the publish and the picker fix shipped the old app under a higher version number. The first picker fix reporting `0 change(s)` and the missing control in the tree view were the only clues. Re-importing the same build with Studio closed worked.
- Before the first import, confirm whoever or whatever does step 4 can reach Studio and is signed in. Otherwise pickers stay broken until someone can.
- Pickers are broken for every user from step 3 until step 6 lands, a matter of minutes if nothing stalls. On an app people are using, run steps 3 to 6 back to back in a quiet window, or use the two box picker and skip steps 4 to 6.
- A script that runs these steps must check that each download produced a fresh file, not only the exit code. The exit code alone missed a failed download, and an older `live.msapp` left in the folder then gets fixed and shipped as if it were the new one.
- Studio edits made after a ship live only in the cloud. Run `app.ps1 pull -Force` and commit before the next source edit, or the next ship overwrites them. The pull brings no `SearchItems` into source, which is correct.

## Small edits in Studio

A handful of formula changes can still be pasted into Studio and published (the procedure is in the `powerapps-build-playbook` skill, manual steps). Then pull the app into the repo (`app.ps1 pull -Force` on a branch) and commit before anyone edits source again. Run the fix script in report mode on the downloaded msapp while you have it. It settles whether picker search is still intact. For larger work, a restyle, a new panel, a batch of pickers, edit source and ship.

## Solutions, ownership, and test copies

The two solutions the ship relies on (the app alone, the flows in their own), what survives a delete and reimport, how to delete a solution for real, moving ownership to a service account, and building a test copy of the app and flows all live in `references/solutions-and-ownership.md`.

## Verification checklist after any import

1. Open the app in Studio.
2. Run App.OnStart once. Without it every `var` is blank and the theme renders as black boxes.
3. Formulas and errors panel: zero red.
4. Click through the changed feature against real SharePoint data.
5. Type a name into a people picker. If it finds nobody, finish the ship procedure from step 4.
6. Remove and re-add a flow in the Power Automate pane only when its inputs or outputs changed (see the `powerapps-troubleshooting` skill, "received 9, expected 7-8"). After an import that changed no flow's inputs or outputs, the flows worked without it. If one looks stale in the pane, Refresh it, then Save and Publish.
7. Every flow in the expected state, on or off, and connection references pointing at the right connections.
8. Have one normal user, not the owner and not the service account, reload the app and click a button that calls a flow. Then confirm a run by that user exists in the flow's history.

Step 8 exists because of one failure that hides from every owner. After a day of command-line imports, flow calls from the published app were rejected for every non-owner before a run existed, so the run history stayed clean and the buttons only showed a generic error. The owner and the service account kept working everywhere, in Studio and in the published app, so every test the builders ran passed. It surfaced days later in front of users. Removing and re-adding the flows and publishing from Studio fixed it within minutes. The cause was never found, and it has one recorded incident. So re-adding is the fix for a failed step 8, not a routine ship step. It was routine for a while and cost a quarter of an hour on every ship.

## The canvas authoring MCP, the other way in

Microsoft's canvas authoring MCP server (the `canvas-apps` plugin in the microsoft/power-platform-skills repo, generally available since September 2026) edits a live Studio session from an agent: `sync_canvas` pulls the open app into local pa.yaml, `compile_canvas` pushes edited pa.yaml back, and `describe_control` returns the real property names and versions for a control. Its docs list no premium licence, Managed Environment or Dataverse requirement. It needs the .NET 10 SDK, an app already saved once in Studio, coauthoring turned on, and the Studio tab kept open while it works.

Where it fits next to pack and ship:

- It edits the app in place in Studio, so the AppId never changes and there is no solution import. Save and Publish in Studio afterwards, then pull into the repo as after any Studio edit.
- `describe_control` replaces guessing property names and control versions from memory (the `AccessibleLabel` and modern rename traps above).
- Classic people pickers break the same way (above), and `sync_canvas` has been reported to drop the hidden data field children that give a Classic combo its Person layout. Use the two box picker, or patch the published msapp as in the ship procedure.
- A big rebuild, a restyle across every screen, or an app nobody can keep a Studio tab open for, still goes through pack and ship.

## Driving Studio from a browser tool

An agent with a browser tool can run the Studio steps of a ship by itself, once a person has signed in. An agent never types the password. These are what the tool does not tell you.

- The Studio canvas and its panes sit in a cross origin frame. Accessibility trees, element search and page scripts see only the portal header around it, so work from screenshots and coordinates. Keep the browser's own desktop viewport. An emulated 1600 by 1000 viewport left Studio unresponsive. Take a new screenshot after anything that changes the layout.
- After Publish, the confirmation dialog can arrive late or never, and Studio then only saves. Read the app's Versions page in the maker portal. If the newest version is not the published one, use Publish this version there.
- The screen lags behind your input, and more so while flows are out of the app and formulas are in error. A menu or list can appear 10 to 20 seconds after the click, and a screenshot can show the state before it. Clicks queue up and land later. Only click a target that a screenshot already shows, and never chain a click on a search result in the same batch as the search.
- Studio opening read only with "you already have editing control elsewhere" is your own earlier session. Override takes it back. If the banner names someone else, stop and ask.
- In the Power Automate pane, Add flow lists every flow in the environment, other apps' flows included. Search the exact name and see the single result before you click it.
- Row menus hold Edit, Refresh and Remove from app close together, and a list that shrinks loses its scrollbar, so the menu button moves sideways. Check the open menu before you click an item. A stray Refresh is harmless but makes the list look stuck.
- When the pane's list is empty, a large Create new flow button sits where the search results were. Clicking it opens the flow designer. Close it, nothing is created until you pick a template.
- In App checker, Formulas lists an Errors group above Warnings. No Errors group means zero errors. Delegation warnings on existing formulas do not count.
- A publish toast from an earlier session can still be on screen. Read the time on it.

Test against real data without changing it. A blank new record form is safe for picker search: type a name, read the list, select nothing.

## What belongs in git

| Item | In git? |
|---|---|
| `Src/*.pa.yaml` | Yes. This is the source. |
| `<App>.msapr` sidecar | Yes. Pack needs it. |
| Packed or downloaded `.msapp` | No. Build artifact. |
| Unpacked solutions (Other/, Workflows/) | Yes. |
| Canvas binary inside the solution unpack | No. |
| `SCHEMA_AS_BUILT.md`, `STUDIO_TODO.md` | Yes. They are the contract and the manual log. |
