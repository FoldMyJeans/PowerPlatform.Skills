# Canvas source workflow. pa.yaml, packing, and the one way door

How a canvas app becomes text you can edit, how it gets back into the cloud, and the single constraint that shapes the whole build order.

---

## The one thing to internalize first: this is a one way door

`pac canvas pack` and `unpack` are a deprecated preview feature. Microsoft's own docs say the generated `.pa.yaml` is read only, for reviewing changes, and the supported source control path (Power Platform Git Integration) requires Dataverse.

In practice the pack direction works, and works well, until the app contains a Studio only rich control:

- A `Classic/ComboBox` (people picker). It needs `SearchItems` at runtime, and pack rejects that property with error PA2108.
- The attachment stack: `Form` plus `TypedDataCard` (variant ClassicAttachmentsEdit) plus `Attachments`.

The moment either exists anywhere in the app, `pac canvas pack` fails for the whole app. Not for that control, for everything. No packaging format dodges it (bare msapp or solution zip, the failure is in YAML to package validation, not the container). This was proven the hard way, twice.

```
Era 1 (before any Studio-only control):
  edit pa.yaml -> pac canvas pack -> import msapp -> test        REPEATABLE

Era 2 (after the first combo box or attachment form goes in):
  edit in Studio -> export or download -> pac canvas unpack -> read, diff, commit
  FOREVER. Never pack again.
```

Practical consequences:

1. Sequence the build. Do everything you possibly can in YAML first, in one continuous era. People pickers and attachment forms go in last, in Studio, as a documented manual batch (the `powerapps-build-playbook` skill).
2. Put placeholders in the YAML where Studio only controls will go (a dashed box, a "people picker added in Studio" label) so the layout is reserved and the manual step is obvious.
3. Once past the door, retire the pack verb from your helper script so nobody packs and imports a stale build over live work.
4. After the door, the repo becomes a changelog. Two ways to keep it true: mirror each confirmed Studio change into the YAML by hand, and periodically run a full export and unpack that trues up everything at once.

### Copy pasting a people picker combo: check SearchFields

Once one `Classic/ComboBox` people picker is built and working, the fast way to add the same picker to another screen or container is copy and paste in Studio, then rename. This works, but paste does not always carry `SearchFields` correctly. A pasted combo can come out with `SearchFields: ["Claims"]` (the raw login string) instead of `SearchFields: ["DisplayName"]`.

This fails silently. The combo still renders, still opens, still lets you pick a person from the dropdown. The only symptom is that typing a person's name to filter the list does not match anything, because it is searching the wrong field. Nothing in Studio flags it as an error. After any copy paste of a people picker, open Advanced on the pasted control and confirm `SearchFields` reads `["DisplayName"]`, not `["Claims"]`.

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
- Control declarations carry a version: `Label@2.5.1`, `Classic/Button@2.2.0`. Copy versions from controls that already exist in the app.
- Containers used are plain `GroupContainer@1.5.0` with `Variant: ManualLayout`, positioned by X and Y. No auto layout containers. Manual positioning is more YAML but it packs and behaves predictably.

Common control set that packs cleanly: `GroupContainer@1.5.0`, `Label@2.5.1`, `Classic/Button@2.2.0`, `Classic/TextInput@2.3.2`, `Classic/CheckBox@2.1.0`, `Classic/DatePicker@2.6.0`, `Gallery@2.15.0` (Variant Vertical or Horizontal), `HtmlViewer@2.1.0`, `Timer`, `Icon`, `Rectangle`.

## The build loop (era 1)

Ship a helper script (`powerapps/app/app.ps1`) with two verbs:

- `pack`: `pac canvas pack --msapp <App>_built.msapp --sources src --layout SourceCode`, then print the import path.
- `pull`: `pac canvas download` plus `pac canvas unpack`, guarded behind a `-Force` flag with a loud warning, because pull overwrites `src/` with the cloud copy and the repo is usually ahead of the cloud.

The loop:

1. Edit `src/Src/scr_*.pa.yaml`.
2. `app.ps1 pack`.
3. Import in the maker portal: Apps, Import canvas app, from this device, pick the built msapp. A YAML packed app shows a one time "validate by opening in Studio" banner. Expected.
4. Open in Studio. Run App.OnStart once (Tree view, App, three dots, Run OnStart) so variables exist.
5. Open the Formulas and errors panel and clear every red error.
6. Fix in YAML, repack, repeat.

The critical mindset: pack success is not correctness. Pack validates YAML structure and the control schema. It does not type check Power Fx. The errors panel after import is the real test. Formula type errors, scope errors, and unknown column errors all surface only there.

On first ever import the data connections must be added once inside Studio (add the SharePoint lists as data sources). After that, re-imports keep them.

## The mirror loop (era 2)

After the one way door, Power Apps Studio is the only editor. Two working styles, use both:

Style 1, paste driven (day to day changes). The developer (or the AI assistant, see the `powerapps-build-playbook` skill) writes the exact Power Fx property values. A human pastes them into Studio, tests, and confirms. Only after confirmation does the same change get mirrored into the repo YAML by hand and committed. Order matters: paste first, confirm, then mirror. Nothing rejected ever lands in git.

Style 2, export driven (periodic true up). On a fresh branch, run the export and unpack helper: `pac solution export`, `pac solution unpack` into the repo, `pac canvas unpack --layout SourceCode` on the msapp inside it, then commit and open a pull request. The helper cuts the branch and opens the PR for you instead of committing to `main`. This captures accumulated Studio work in one PR and corrects any drift from hand mirroring.

The repo in era 2 is a reviewable changelog of the live app, and the protection rules (protected main, PRs) keep it honest.

## Solutions: the long term container

Even without Dataverse tables, flows and (optionally) the canvas app live in a Dataverse solution, because that is the unit Power Automate exports and imports. The unpacked solution layout:

```
powerapps/flows/<SolutionName>/
  Other/
    Solution.xml            manifest: solution name, version, publisher, root components
    Customizations.xml
  Workflows/
    <FlowName>-<GUID>.json           the flow definition (the code)
    <FlowName>-<GUID>.json.data.xml  sidecar: name, type, state
  CanvasApps/
    <prefix>_<appname>_<hash>.meta.xml
    <prefix>_<appname>_<hash>_DocumentUri.msapp    gitignore this binary
```

Putting the canvas app into the solution too means one export captures app plus flows together. The solution version (`<Version>` in Solution.xml) ticks up on each export, which gives you a rough release number for free.

Take the app back out for flow work. Once a build hits the stage of editing flow JSON by hand and reimporting, the app riding along makes every export and import slow and large, and worse, an import can overwrite live Studio work on the app. The pattern that worked: app in the solution for an occasional true up export, app out of the solution for every flow edit cycle. Removing it from the solution does not delete or affect the app itself.

## What survives a delete and reimport, and what does not

Sooner or later something has to be rebuilt: a new owner, a botched import, a move. Four facts decide whether that is an afternoon or a week.

Deleting a solution deletes the container, not the contents. The app and every flow stay in the environment, still running, now sitting in the default solution. Deleting the solution and importing a fresh copy therefore updates the same components rather than recreating them, which is exactly what you do not want if the point was to recreate them. Delete the components explicitly first.

Flows keep their GUID, the canvas app does not. `Customizations.xml` pins each flow as `<Workflow WorkflowId="{...}" Name="...">`, and import recreates the workflow record with that same id. Since a canvas app references its flows by id, the app's wiring survives a delete and reimport untouched, with no re-adding in the Power Automate pane. A canvas app gets a new app id, so its play URL changes, and every deep link built from it breaks. Grep the app source for the old id before you start, so you know how many buttons to repoint.

Connection references belong to whoever created them, and an import that touches one it does not own fails with a `WriteAccess` error naming a connection reference record. This is what stops a second account importing a solution built by the first. Delete the orphaned references first, or have the new owner import a solution whose references it can create fresh. Where a reference is shared with another app, leave it alone and give this solution its own instead.

Import activates flows. A flow exported in a draft state comes back on, so a change you meant to stage lands live. Check the state of every flow after an import and turn back off anything that was meant to stay off.

## Ownership: put the app under a service account

An app owned by a person is a dependency on that person. When they change roles the flows stop, the emails stop, and nobody else can edit it. The pattern that holds: a service account owns the app and the flows, a security group of the developers is co-owner on both, and the flows run on the service account's connections so outgoing mail comes from the service rather than a person.

Do it on day one. Retrofitting is a migration, and this document exists because one was needed.

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
5. If a flow signature changed, remove and re-add the flow in the Power Automate pane (see the `powerapps-troubleshooting` skill, "received 9, expected 7-8").
6. Every flow in the expected state, on or off, and connection references pointing at the right connections.

## What belongs in git

| Item | In git? |
|---|---|
| `Src/*.pa.yaml` | Yes. This is the source. |
| `<App>.msapr` sidecar | Yes. Pack needs it. |
| Packed or downloaded `.msapp` | No. Build artifact. |
| Unpacked solution (Other/, Workflows/) | Yes. |
| Canvas binary inside the solution unpack | No. |
| `SCHEMA_AS_BUILT.md`, `STUDIO_TODO.md` | Yes. They are the contract and the manual log. |
