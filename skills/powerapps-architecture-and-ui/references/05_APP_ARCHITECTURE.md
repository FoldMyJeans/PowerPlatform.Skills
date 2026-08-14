# 05: App architecture. The single screen shell

The apps built with this playbook are single screen applications. The app never navigates between Studio screens. It stays on one screen and swaps which containers are visible using variables. This doc is the shell: view state, OnStart, OnVisible, theme, and naming.

---

## Why one screen

- Power Apps requires globally unique control names, so you cannot copy a shared panel onto four screens. One screen means shared panels (documents, approvals, stepper) exist once and are made route aware with `Switch`.
- Navigation state is one variable instead of `Navigate()` scattered everywhere.
- Everything that must react together (top bar, stepper, step containers) lives in one scope.

The cost is one large YAML file and careful `Visible` discipline. Worth it every time so far.

## The container tree

```
scr_Main  (the only screen)
└─ con_App                    master container, full screen
   ├─ con_TopBar              always visible: logo, route badge, Home button, stepper gallery
   ├─ con_Menu                the home directory of entry buttons      (varView = "MENU")
   ├─ con_Guide / con_Verdict guided routing questions and result      ("GUIDE", "VERDICT")
   ├─ con_RouteFull / ...     one container per route or per step
   │    └─ con_Step1..N       one container per step inside the route
   ├─ con_Docs                SHARED documents panel (all routes)
   ├─ con_Approvals           SHARED approval panel (all routes)
   ├─ con_FolderGate          SHARED "create the folder first" gate
   ├─ con_Tracker             dashboard: all records                    ("TRACKER")
   ├─ con_ApprovalsDash       dashboard: approval workload              ("APPROVAL_DASH")
   └─ tmr_Notify_Debounce     hidden timer, last child (see 07_UI_PATTERNS.md)
```

Containers are plain manual layout group containers positioned by X and Y. No auto layout.

## View state

One string variable decides what shows:

```
// App.OnStart
Set(varView, "MENU");

// every top level container
Visible: =varView = "FULL_FLOW"

// navigating
OnSelect: =Set(varView, "FULL_FLOW")
```

Step containers add the step condition. The standard visibility formula, including a dev override and the stepper browse state:

```
// container for step 2 of the full flow
Visible: =varView = "FULL_FLOW"
    && !IsBlank(varDeal)
    && If(varViewStep > 0, varViewStep, varDeal.Current_Step) = 2
```

The `varViewStep` part is the clickable stepper pattern (browse a step without moving the record), detailed in 07_UI_PATTERNS.md. A useful addition is `varDevStep` (0 is normal, 1 to 8 force shows a step for debugging) and a SubStep condition for A and B phases.

## App.OnStart: the numbered sections

Structure OnStart as commented, numbered sections. This is the proven order:

```
// 1) DEV OVERRIDE
Set(varDevStep, 0);

// 2) CORE CONTEXT
Set(varDeal, Blank());
Set(varView, "MENU");

// 3) DEEP LINK HANDLER (see below)

// 4) PER FEATURE STATE DEFAULTS
Set(varViewStep, 0);
Set(varStep5_SubStep, "A");
// ... every step flag, counter, and sort default

// 5) SEND NOTIFICATION GATE
Set(varSendNotification_Ready, true);
Set(varSendNotification_TimerStart, false);

// 6) TYPED DEFAULTS (patch safety, see 06_POWERFX_RULES.md in the `powerapps-powerfx` skill)
Set(varReviewDefault, Defaults(Approvals));

// 7) THEME (see below)

// 8) USER CACHE
Set(varUserEmailLower, Lower(User().Email));

// 9) ROLE MAPPING (from the roles list)
Set(varCOO, LookUp(Role_Config, Role_Name.Value = "COO").Assigned_To);

// 10) GLOBAL ROLE CHECK
Set(varIsAdminOrGlobalRole,
    !IsBlank(LookUp(Role_Config,
        Role_Name.Value = "Admin" && Lower(Assigned_To.Email) = varUserEmailLower))
    || varUserEmailLower = Lower(Coalesce(varCOO.Email, ""))
    /* || the other global roles */ );
```

Two operational facts about OnStart:

- In Studio, OnStart does not run by itself while editing. After any OnStart change, right click App in the tree view and Run OnStart, otherwise every variable is blank and themed controls render black.
- OnStart runs once per app load. Anything that must survive a refresh or reflect live data belongs in OnVisible, not here.

## Deep links

Every notification email links to the app with `&dealId=<id>` appended (and optionally `&view=<step>`). OnStart section 3 handles it:

```
If(
    !IsBlank(Param("dealId")),
    Set(varDeal, LookUp(Deals, ID = Value(Param("dealId"))));
    If(
        IsBlank(varDeal) || Coalesce(varDeal.Is_Locked, false),
        Set(varDeal, Blank()); Set(varView, "MENU"),
        Set(varView, "PROCESS")   // or compute the record's route view
    )
);
```

The `view` parameter refinement: the email can force which step view the recipient lands on, as a local only overlay that patches `varDeal` in memory (never SharePoint), so an approver clicking an approval email lands on the approval panel even if the live step has moved. Locked records skip everything and land on Home.

The app play URL that emails point at comes from the maker portal (Apps, Details, Web link). It is environment specific. Buttons that pass it to flows must carry the real URL, a placeholder here is the classic dead email link bug.

## scr.OnVisible: the data sync point

OnVisible runs on load and whenever the screen becomes visible again. It is the only place local mirrors get rehydrated from SharePoint. The proven step order:

```
// 1  Refresh every data source
Refresh(Deals); Refresh(Deal_Files);
Refresh(Approvals); Refresh(Role_Config);

// 2  Safe record reload (never trust the stale local copy)
If(!IsBlank(varDeal),
    Set(varDeal, LookUp(Deals, ID = varDeal.ID)),
    Set(varView, "MENU"));

// 3  Auto clear stale dev override when the record changed

// 4  Mirror sync: local UI mirrors re-read from SharePoint
Set(varStep5_SubStep, Coalesce(varDeal.SubStep.Value, "A"));

// 5  Re-cache the user email

// 6  Recompute the numeric step for the progress bar

// 7  Reset per step state when the loaded record CHANGED
//    (compare varPrevDealID against varDeal.ID)

// 8+ Evidence checks (file counts), permission flags (varStepN_CanEdit),
//    approval counts and flags, all recomputed fresh

// 13.5 Rehydrate persisted UI state, for example a saved confirmation
//    flag that drives a green button state, from its SharePoint columns

// 15 Track state for next time
Set(varPrevDealID, If(IsBlank(varDeal), Blank(), varDeal.ID));

// 16 Build display collections
ClearCollect(colProcessSteps,
    { StepNum: 1, StepName: "Request", Status: If(1 < varStepNum, "Completed",
        If(1 = varStepNum, "In Progress", "Locked")) },
    /* ... one row per step ... */ );
```

The principle behind every step: SharePoint is the source of truth, local variables are mirrors. Any state that drives UI and survives navigation must be re-derivable from SharePoint here, or it will be wrong after a refresh. The named bug this prevents: a "saved" green state that vanishes on reload because it only ever lived in a variable.

## The theme

One record in OnStart, referenced by every control:

```
Set(varTheme, {
    Primary:   ColorValue("#667eea"),
    Secondary: ColorValue("#764ba2"),
    Success:   ColorValue("#22c55e"),
    Warning:   ColorValue("#f59e0b"),
    Danger:    ColorValue("#ef4444"),
    Info:      ColorValue("#3b82f6"),
    Light:     ColorValue("#f9fafb"),
    Dark:      ColorValue("#1f2937"),
    Border:    ColorValue("#e5e7eb"),
    White:     ColorValue("#ffffff")
});
```

Rule: `Fill: =varTheme.Primary`, never `Fill: =RGBA(102,126,234,1)`. Two allowed exceptions: inline CSS inside HtmlViewer controls (they cannot read app variables) and intentional gradient headers. Hardcoded colors were the one shortcut that got regretted in production. Do it right from the start: even a route colored top bar switches `con_TopBar.Fill` from theme colors, and controls that must match it reference `con_TopBar.Fill`.

## Naming conventions

Any new control or variable follows them:

Controls, by prefix: `btn_` button, `lbl_` label, `lblHdr_` and `lblCol_` gallery header and column labels, `txt_` text input, `cmb_` combo box, `chk_` checkbox, `tgl_` toggle, `dp_` date picker, `frm_` form, `dc_` data card, `att_` attachment control, `gal_` gallery, `con_` or `cnt_` container, `htm_` HTML viewer, `ico_` icon, `rec_` rectangle, `tmr_` timer, `cmp_` component, `scr_` screen.

Scope in the middle: `btn_Step7_Approve`, `lbl_S1_SalesVal`, `cmb_Step5_Network_SME`. The scope token matches the container or step the control lives in.

Variables: everything starts with `var`. `var<Concept>` for app wide (`varTheme`, `varDeal`, `varUserEmailLower`), `varStep<N>_<Concept>` for step scoped (`varStep7_AllApproved`), `varStep<N><Sub>_<Concept>` for substep scoped (`varStep5A_FormDirty`). Collections start with `col`.

Rename debt is real. One production build needed a dedicated cleanup pass with a rename map (old name to new name) because auto generated names (`Rectangle1`, `DataCardValue1`) and inconsistent prefixes made every conversation about the app ambiguous. Name things correctly at creation and you never pay that tax. If you do rename later: bulk find and replace in the YAML in VS Code is safe for mechanical renames, then test in Studio, and keep a rename map doc for old commits and screenshots.

## Copy rules for on screen text

Professional register for a senior audience. Spell out acronyms on first use, never show bare codes (write "Change request review (form CR2)", not "CR2"). Use the % sign instead of the word percent. No em or en dashes, no semicolons in labels. Buttons that move the record are named for where it goes ("Move to: Financial analysis"), not generic "Next".
