# check.ps1
# Enforces the rules in AGENTS.md. Run from the repo root before every commit:
#   pwsh -File tools\check.ps1
# Exit code 0 means clean. Any finding prints FAIL with the file and line and exits 1.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = @()

function Add-Fail($file, $line, $msg) {
    $rel = $file.Replace("$root\", '')
    $script:fail += [pscustomobject]@{ File = $rel; Line = $line; Problem = $msg }
}

# Strip fenced code blocks so code samples are exempt from the prose rules. Power Fx uses
# semicolons as statement separators, so the semicolon rule would fire on every formula.
function Get-ProseLines($path) {
    $inFence = $false
    $n = 0
    foreach ($line in (Get-Content $path)) {
        $n++
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if (-not $inFence) {
            # Inline code spans are code too. `Refresh(a); Reset(b)` is not a prose semicolon.
            [pscustomobject]@{ N = $n; Text = ($line -replace '`[^`]*`', '') }
        }
    }
}

$mdFiles = Get-ChildItem $root -Recurse -Filter *.md |
    Where-Object { $_.FullName -notlike '*\.git\*' }

foreach ($f in $mdFiles) {
    foreach ($l in Get-ProseLines $f.FullName) {
        if ($l.Text -match '[–—]') { Add-Fail $f.FullName $l.N 'em dash or en dash in prose' }
        if ($l.Text -match ';')    { Add-Fail $f.FullName $l.N 'semicolon in prose' }
    }
}

# Skill folder rules.
$skillDirs = Get-ChildItem "$root\skills" -Directory
foreach ($d in $skillDirs) {
    $skillMd = Join-Path $d.FullName 'SKILL.md'
    if (-not (Test-Path $skillMd)) { Add-Fail $d.FullName 0 'skill folder has no SKILL.md'; continue }

    $raw = Get-Content $skillMd -Raw
    $lineCount = (Get-Content $skillMd).Count

    if ($lineCount -gt 150) { Add-Fail $skillMd $lineCount "SKILL.md is $lineCount lines, cap is 150" }

    $fm = [regex]::Match($raw, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $fm.Success) { Add-Fail $skillMd 1 'no YAML frontmatter'; continue }

    $name = [regex]::Match($fm.Groups[1].Value, '(?m)^name:\s*(\S+)').Groups[1].Value
    if ($name -ne $d.Name) { Add-Fail $skillMd 2 "frontmatter name '$name' does not match folder '$($d.Name)'" }

    $desc = [regex]::Match($fm.Groups[1].Value, '(?s)description:\s*>-\s*\r?\n(.*)$').Groups[1].Value -replace '\s+', ' '
    $desc = $desc.Trim()
    if ($desc.Length -eq 0)    { Add-Fail $skillMd 3 'description is empty or not a >- block' }
    if ($desc.Length -gt 1024) { Add-Fail $skillMd 3 "description is $($desc.Length) chars, cap is 1024" }

    # Reference files stay loadable on their own. The cap is a proxy for the real rule, one
    # topic per reference. A file that needs more than this is usually covering two topics.
    Get-ChildItem (Join-Path $d.FullName 'references') -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object {
        $rc = (Get-Content $_.FullName).Count
        if ($rc -gt 300) { Add-Fail $_.FullName $rc "reference is $rc lines, cap is 300, split it by topic" }
    }
}

# Reference filenames describe their content. A numeric prefix carries no retrieval signal and
# encodes a reading order that stopped existing when the playbook was split into skills.
Get-ChildItem "$root\skills" -Recurse -Filter *.md |
    Where-Object { $_.Name -match '^\d' } | ForEach-Object {
        Add-Fail $_.FullName 0 'numeric filename prefix, name the file for its content'
    }

# No path reference may leave its own skill folder. Point by skill name instead.
$skillNames = ($skillDirs | ForEach-Object { $_.Name }) -join '|'
$pathPatterns = @(
    @{ Rx = '(?<![.\w])\.\./';                     Msg = 'relative path escapes the skill folder' }
    @{ Rx = "(?:$skillNames)[\\/]references[\\/]"; Msg = 'cross skill path, name the skill instead of its path' }
    @{ Rx = "(?<!agents[\\/])skills[\\/](?:$skillNames)"; Msg = 'repo relative path, name the skill instead' }
)
Get-ChildItem "$root\skills" -Recurse -Include *.md, *.json | ForEach-Object {
    $file = $_.FullName
    $n = 0
    foreach ($line in (Get-Content $file)) {
        $n++
        foreach ($p in $pathPatterns) {
            if ($line -match $p.Rx) { Add-Fail $file $n $p.Msg }
        }
    }
}

# Every `references/x.md` pointer must resolve inside its own skill. A pointer that names a
# file living in a different skill reads as intra skill and silently misleads.
foreach ($d in $skillDirs) {
    Get-ChildItem $d.FullName -Recurse -Filter *.md | ForEach-Object {
        $src = $_.FullName
        $n = 0
        foreach ($line in (Get-Content $src)) {
            $n++
            foreach ($m in [regex]::Matches($line, 'references/([A-Za-z0-9._-]+\.(?:md|json))')) {
                $target = Join-Path $d.FullName "references\$($m.Groups[1].Value)"
                if (-not (Test-Path $target)) {
                    Add-Fail $src $n "points at references/$($m.Groups[1].Value), which does not exist in this skill"
                }
            }
        }
    }
}

# Redaction. No real company, tenant, or instance names anywhere in the repo.
# Add local terms in tools\banned.local.txt, one regex per line, blank lines and # comments
# skipped. Git ignores that file, so terms specific to your own environment stay out of the
# repo. The check runs fine without it.
$banned = @(
    @{ Rx = '(?i)https?://(?!<tenant>)[a-z0-9-]+\.sharepoint\.com'; Msg = 'real SharePoint tenant, use <tenant>.sharepoint.com' }
    @{ Rx = '(?i)https?://(?!<yourorg>)[a-z0-9-]+\.crm\d*\.dynamics\.com'; Msg = 'real Dataverse org, use <yourorg>.crm.dynamics.com' }
    @{ Rx = '(?i)\b[a-z0-9._%+-]+@(?!yourcompany\.com|example\.com)[a-z0-9.-]+\.[a-z]{2,}\b'; Msg = 'real looking email address, use you@yourcompany.com' }
)
$localTerms = Join-Path $PSScriptRoot 'banned.local.txt'
if (Test-Path $localTerms) {
    foreach ($line in Get-Content $localTerms) {
        $rx = $line.Trim()
        if ($rx -and -not $rx.StartsWith('#')) {
            $banned += @{ Rx = "(?i)$rx"; Msg = 'local banned term, use a placeholder' }
        }
    }
}
Get-ChildItem $root -Recurse -Include *.md, *.json, *.ps1 |
    Where-Object { $_.FullName -notlike '*\.git\*' } | ForEach-Object {
        $file = $_.FullName
        $n = 0
        foreach ($line in (Get-Content $file)) {
            $n++
            foreach ($b in $banned) {
                if ($line -match $b.Rx) { Add-Fail $file $n $b.Msg }
            }
        }
    }

# Every JSON in the repo must parse.
Get-ChildItem $root -Recurse -Filter *.json |
    Where-Object { $_.FullName -notlike '*\.git\*' } | ForEach-Object {
        $jsonFile = $_.FullName
        try { Get-Content $jsonFile -Raw | ConvertFrom-Json | Out-Null }
        catch { Add-Fail $jsonFile 0 "invalid JSON: $($_.Exception.Message)" }
    }

# Every reference file must be listed in its own SKILL.md, so a new one cannot be orphaned.
foreach ($skillDir in $skillDirs) {
    $skillMd = Join-Path $skillDir.FullName 'SKILL.md'
    if (-not (Test-Path $skillMd)) { continue }
    $skillText = Get-Content $skillMd -Raw
    $refDir = Join-Path $skillDir.FullName 'references'
    if (-not (Test-Path $refDir)) { continue }
    Get-ChildItem $refDir -File | ForEach-Object {
        if ($skillText -notmatch [regex]::Escape($_.Name)) {
            Add-Fail $skillMd 0 "reference '$($_.Name)' is not mentioned in SKILL.md"
        }
    }
}

# Every skill folder must be listed in README.md, so a new skill cannot ship undiscoverable.
$readme = Get-Content (Join-Path $root 'README.md') -Raw
foreach ($d in $skillDirs) {
    if ($readme -notmatch [regex]::Escape($d.Name)) {
        Add-Fail (Join-Path $root 'README.md') 0 "skill '$($d.Name)' is not listed in README.md"
    }
}

if ($fail.Count -eq 0) {
    Write-Output "PASS. $($mdFiles.Count) markdown files, $($skillDirs.Count) skills, no findings."
    exit 0
}

Write-Output "FAIL. $($fail.Count) finding(s):"
$fail | Sort-Object File, Line | Format-Table -AutoSize | Out-String | Write-Output
exit 1
