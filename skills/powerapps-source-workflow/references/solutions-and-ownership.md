# Solutions, ownership, and test copies

The containers a ship moves through, what a delete really deletes, who should own the app, and how to stand up a test copy without touching production.

---

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

Deleting an unmanaged solution deletes the container, not the contents. The app and every flow stay in the environment, still running, now sitting in the default solution. Deleting the solution and importing a fresh copy therefore updates the same components rather than recreating them, which is exactly what you do not want if the point was to recreate them. Delete the components first, then the solution:

1. Open the solution's Objects view, select all, Remove, Delete from this environment. A solution of over a dozen flows took about two minutes.
2. `pac solution delete --solution-name <SolutionName>`.

Flows keep their GUID, the canvas app does not. `Customizations.xml` pins each flow as `<Workflow WorkflowId="{...}" Name="...">`, and import recreates the workflow record with that same id. Since a canvas app references its flows by id, the app's wiring survives a delete and reimport untouched, with no re-adding in the Power Automate pane. A canvas app gets a new app id, so its play URL changes, and every deep link built from it breaks. Grep the app source for the old id before you start, so you know how many buttons to repoint. A normal ship is an update, not a delete, and keeps the id.

Connection references belong to whoever created them, and an import that touches one it does not own fails with a `WriteAccess` error naming a connection reference record. This is what stops a second account importing a solution built by the first. Delete the orphaned references first, or have the new owner import a solution whose references it can create fresh. Where a reference is shared with another app, leave it alone and give this solution its own instead.

Import activates flows. A flow exported in a draft state comes back on, so a change you meant to stage lands live. Check the state of every flow after an import and turn back off anything that was meant to stay off. An import can also print "The original workflow definition has been deactivated and replaced". On the build that printed it, every flow was still on afterwards, so read it as a note and check the states anyway.

## Ownership: put the app under a service account

An app owned by a person is a dependency on that person. When they change roles the flows stop, the emails stop, and nobody else can edit it. The pattern that holds: a service account owns the app and the flows, a security group of the developers is co-owner on both, and the connection references point at the service account's connections. Every embedded connection and every automated flow then acts and mails as the service rather than a person. An app called flow whose connection is set to `invoker` still acts as whoever clicked, whoever owns it (the `powerapps-approvals-and-flows` skill).

Do it on day one. Retrofitting is a migration.

The mechanics are two different jobs, and neither is self service.

- Canvas app: `Set-AdminPowerAppOwner` from `Microsoft.PowerApps.Administration.PowerShell`, which needs a Power Platform admin. Re-share the previous owner as co-owner straight afterwards, otherwise they lose the access that `pac canvas download` depends on.
- Solution aware flows: these are Dataverse records, so `Set-AdminFlowOwnerRole` does not apply. An administrator reassigns them in the Dataverse Processes list.

Ownership and runtime identity are separate. Changing the owner moves a field and nothing else. The flows keep running on the old owner's connections until someone signs in as the service account and repoints each connection reference, and that is the step that actually gets a personal name off the emails.

Solution aware flows have no "Run only users" panel, so do not go looking for one. Users of the app get run access through the app's own sharing.


## A test copy of the app and its flows

Testing a change against production lists sends real mail and writes real rows. The pattern that worked keeps a full second copy next to production, built by a script instead of by hand:

- A generator copies the app solution and the flow solution into a second pair of solutions, with every list id, flow id and app id rewritten to the test copies (test lists on a test site, test flows, a test app).
- A guard in the generator refuses to write any package that still contains a production id. Grep for each production list GUID, flow GUID and app id, and fail on the first hit.
- Every flow's mail goes to one tester address, whatever the recipients input says.
- Every script downloads by app id. A test app named "TEST - <App>" makes a download by the production name fail, because `--name` matches partially (`references/environment-setup.md`).

Do not plan the test copy around a developer environment. Unmanaged ones can no longer be created from 2026-11-15 and are suspended from 2026-12-15, and running apps or flows in a managed one needs premium. A copy next to production, or in a sandbox environment, stays on standard licensing.

The test copy ships with the same procedure as production. Run the ship there first, then repeat it on production in a quiet window.
