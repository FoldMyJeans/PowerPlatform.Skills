# 02: Environment setup. Tools, authentication, and the repo layout

One time setup for a Windows machine. After this, the daily loop is one command.

---

## Install

1. Git. https://git-scm.com/download/win
2. Power Platform CLI (`pac`). https://aka.ms/PowerPlatformCLI
3. VS Code (or any editor). VS Code is the viewer, diff tool, and search tool. It is not the app IDE, Power Apps Studio is.
4. Optional: GitHub CLI (`gh`) if you want to open and merge pull requests from the terminal.

## Configure git

Set your identity. Use a per repo identity (no `--global`) if you separate work and personal:

```powershell
git config user.name "Your Name"
git config user.email "you@yourcompany.com"
```

## Authenticate pac to your environment

```powershell
pac auth create --environment https://<yourorg>.crm.dynamics.com
```

Find the environment URL in the maker portal under Settings, Session details, or in the Power Platform admin center. The auth token expires from time to time. When any `pac` command says authentication required, re-run the same command.

Keep a second profile for the account that owns the solution. `pac auth create --name <label>` adds one, `pac auth list` shows them, `pac auth select --name <label>` switches. Once ownership moves to a service account, `pac solution export` only works from that account's profile, because a maker cannot read connection reference records another user owns. `pac canvas download` still works from either, co-ownership is enough.

## Connections rot quietly

A connection that has sat unused for months still reports "Connected" in the list while its refresh token is long dead. Nothing surfaces until a flow tries to run and fails with a token exchange error, or the owner gets a mail saying the connection needs signing in again.

Do not use Reconnect. It re-authenticates the connection but leaves the permission list behind it broken, and flows then fail to turn on with `Permission denied due to missing connection ACL`, which reads like a different problem entirely and costs an hour.

Create a brand new connection instead, then repoint the connection reference at it (in the solution, Connection references, Edit, pick the new connection, Save). Every flow that shares that reference is fixed in one move. Delete the dead connection afterwards, but read the dialog first, it lists the other apps and flows still using it.

## Windows gotchas that will bite on day one

| Symptom | Fix |
|---|---|
| `'pac' is not recognized` in a fresh shell | The installer updated PATH but the shell predates it. Refresh: `$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")` |
| `running scripts is disabled on this system` | `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| OneDrive sync fights git | Keep repos out of OneDrive. Use `C:\Users\<you>\source\repos\` |
| LF and CRLF warnings on every commit | Add a `.gitattributes` with `* text=auto` |

## The pac commands you will actually use

```powershell
# Canvas app, direct (before the one way door, see 03_SOURCE_WORKFLOW.md)
pac canvas list
pac canvas download --name "<App Display Name>" --file-name app.msapp --overwrite
pac canvas unpack --msapp app.msapp --sources src --layout SourceCode
pac canvas pack   --msapp built.msapp --sources src --layout SourceCode

# Solution (the app plus its flows, the long term container)
pac solution export --name <SolutionName> --path C:\temp\sol.zip --overwrite
pac solution unpack --zipfile C:\temp\sol.zip --folder <repo-folder>
pac solution pack   --zipfile C:\temp\sol_build.zip --folder <repo-folder>
pac solution import --path C:\temp\sol.zip --async --max-async-wait-time 8
```

Always use `--layout SourceCode` on canvas unpack. It produces the readable one file per screen YAML that diffs cleanly in git. The default is the Experimental layout, which emits `*.fx.yaml` files and a different tree, so one unpack without the flag against a repo whose history is SourceCode rewrites the whole thing.

`pac solution import` takes `--async`. Without it the CLI prints nothing at all while the import runs: no output, no progress, no error. That silence looks exactly like a hang, and on one build it was mistaken for one for months, which is how the maker portal ended up written down as the only way to import a solution. It is not. With `--async` the command streams progress lines and returns a result, about four minutes on a thirteen flow solution. Import from the command line every time.

There is no `pac flow list`. To enumerate the cloud flows in an environment and see which are on, fetch them from the `workflow` entity:

```powershell
pac env fetch --xmlFile flows.xml
```

where `flows.xml` holds a FetchXML query over `workflow`, filtered to `category` 5 (cloud flows), selecting `name` and `statecode`. The flag is `--xmlFile`. There is no `--xml`, and the error you get for passing one does not suggest the right flag.

## One repo per app

Every app gets its own private GitHub repo. The layout that worked:

```
<AppName>/
  README.md                       the redacted front door
  .gitignore
  .gitattributes                  * text=auto
  knowledgebase/                  numbered business and design docs (01_..., 02_...)
  mockup/                         the clickable HTML prototype, if the app had one
  powerapps/
    00_README.md ... 09_*.md      the app design docs (architecture, data model, steps,
                                  approvals, automation, access, build plan)
    SCHEMA_AS_BUILT.md            the real SharePoint list and column names
    app/
      app.ps1                     pull helper (download live app and unpack)
      src/                        canvas source: Src/App.pa.yaml, Src/scr_<X>.pa.yaml
      STUDIO_TODO.md              the manual steps log (see 10_MANUAL_STEPS.md in the `powerapps-build-playbook` skill)
    flows/
      <SolutionName>/             unpacked solution: Other/, Workflows/, CanvasApps/
  source_files/                   confidential originals. GITIGNORED, never pushed
```

The knowledgebase folder is what you upload to an AI assistant's project knowledge. Keep one topic per file, numbered. See 12_WORKING_WITH_AI.md in the `powerapps-build-playbook` skill.

## What gets gitignored

```gitignore
# OS and editor junk
.DS_Store
Thumbs.db
desktop.ini
.vs/
*.suo
*.user

# Office lock files
~$*

# Confidential source material, never publish
source_files/
mockup/logo.png

# Local only working files
00_PROJECT_SETUP.md
NEW_PROJECT_RUNBOOK.md

# Build artifacts, regenerated from source
powerapps/app/*.msapp
powerapps/flows/*_build.zip
powerapps/flows/*/CanvasApps/*.msapp
```

Two rules behind that list. First, binary `.msapp` files are build artifacts, the unpacked YAML is the source, so the binaries stay out (they add hundreds of KB per commit and diff as "binary file changed"). Second, anything confidential (original business documents, real logos) never enters git at all. The repo is written redacted from the start: company name replaced with an alias, people replaced with role titles. See 12_WORKING_WITH_AI.md in the `powerapps-build-playbook` skill for the redaction convention.

## The pull request workflow

Every change goes on its own branch and lands through a pull request. Nothing is committed straight to `main`. Protect `main` once the app is live so this is enforced, not just a habit (see 03_SOURCE_WORKFLOW.md for how this maps to the two eras).

The loop is the same for docs and for source:

```powershell
git checkout -b my-change
# make your edits (for a canvas app: export and unpack first)
git add -A
git commit -m "what changed"
git push -u origin my-change
gh pr create
```

Merge on GitHub after review. Zero approvals is fine when you work alone. Use one branch and one PR per feature or fix, not one giant "multiple fixes" commit.

For a canvas app edited in Studio, the export step is the same three pac commands: `pac solution export`, `pac solution unpack`, then `pac canvas unpack --layout SourceCode`. Run them on your branch before you add and commit. The export and unpack helper cuts a branch and opens a PR for you, so the cloud changes still land as a reviewable PR instead of a commit straight to `main`.

## Git discipline that proved worth it

- Protect `main` once the app is live. Require a pull request (zero approvals is fine when you work alone), block force pushes. Every change lands as one squash merged PR, so main reads one entry per finished piece of work.
- Commit messages describe the change in app terms ("Add validation to client name field"), because the YAML diff under it can be thousands of lines of re-indentation.
- The repo is the source of truth for history. The cloud is the source of truth for the running app. Know which direction sync flows in your current era (03_SOURCE_WORKFLOW.md) and never run a pull that overwrites hand authored source without a `-Force` style guard.
