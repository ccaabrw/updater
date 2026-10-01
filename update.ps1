<#
.SYNOPSIS
    Update a file in a git repository via a temporary shallow clone.

.DESCRIPTION
    Makes a shallow clone of a git repository in a temporary directory, lets
    the user edit a file, then commits and pushes the change back to the
    source repository. The temporary clone is removed if all steps succeed;
    on error it is kept so that the work is not lost.

    The editor is taken from $env:VISUAL, then $env:EDITOR, falling back to
    notepad on Windows and vi elsewhere.

.PARAMETER Repository
    URL or path of the existing git repository.

.PARAMETER File
    Path of the file to edit, relative to the repository root.

.PARAMETER Branch
    Branch to clone and push to (default: the remote default branch).

.PARAMETER Message
    Commit message (default: prompt for one, suggesting "Update <file>").

.EXAMPLE
    .\update.ps1 -Message "Fix typo" https://github.com/example/project.git docs/index.md
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Repository,

    [Parameter(Position = 1)]
    [string]$File,

    [Alias('b')]
    [string]$Branch,

    [Alias('m')]
    [string]$Message
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptName = Split-Path -Leaf $PSCommandPath

if (-not $Repository -or -not $File) {
    [Console]::Error.WriteLine("Usage: $scriptName [-Branch branch] [-Message message] <repository> <file>")
    exit 2
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('Error: git is not installed or not on PATH')
    exit 1
}

# A local path must be given as a file:// URL for --depth to be honoured.
if (Test-Path -LiteralPath $Repository -PathType Container) {
    $Repository = [Uri]::new((Resolve-Path -LiteralPath $Repository).ProviderPath, [UriKind]::Absolute).AbsoluteUri
}

# Git uses forward slashes.
$File = $File -replace '\\', '/'

function Read-Answer([string]$Prompt) {
    try {
        $answer = Read-Host -Prompt $Prompt
    } catch {
        $answer = $null
    }
    if ($null -eq $answer) { return '' }
    return $answer
}

function Get-EditorCommand {
    $editor = $env:VISUAL
    if (-not $editor) { $editor = $env:EDITOR }
    if (-not $editor) {
        if ($env:OS -eq 'Windows_NT' -or $IsWindows) { return , @('notepad') }
        return , @('vi')
    }
    # A bare path (possibly containing spaces) is used as-is; otherwise split
    # into a command and arguments, honouring double quotes, e.g.
    # "C:\Program Files\Editor\editor.exe" --wait
    if (Test-Path -LiteralPath $editor -PathType Leaf) { return , @($editor) }
    $parts = [regex]::Matches($editor, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') }
    return , @($parts)
}

$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('updater-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
New-Item -ItemType Directory -Path $tmpDir | Out-Null

# 'remove' deletes the clone on exit; 'keep' leaves it and reports where it is.
$onExit = 'remove'
$exitCode = 1
$errorText = $null
$pushed = $false
$inTmpDir = $false

try {
    Write-Host "Cloning $Repository into $tmpDir ..."
    $cloneArgs = @('clone', '--depth', '1')
    if ($Branch) { $cloneArgs += @('--branch', $Branch) }
    $cloneArgs += @('--', $Repository, $tmpDir)
    & git @cloneArgs
    if ($LASTEXITCODE -ne 0) { throw 'clone failed' }

    Push-Location -LiteralPath $tmpDir
    $inTmpDir = $true
    $onExit = 'keep'

    $newFile = $false
    if (-not (Test-Path -LiteralPath $File)) {
        $answer = Read-Answer "File '$File' does not exist in the repository. Create it? [y/N]"
        if ($answer -notmatch '^[Yy]') {
            $onExit = 'remove'
            throw "file '$File' not found"
        }
        New-Item -ItemType File -Path $File -Force | Out-Null
        $newFile = $true
    }

    $editorCmd = Get-EditorCommand
    $editorExe = $editorCmd[0]
    $editorArgs = @($editorCmd | Select-Object -Skip 1)
    $filePath = (Resolve-Path -LiteralPath $File).ProviderPath
    # Start-Process -Wait also waits for GUI editors such as notepad.
    $argList = @($editorArgs) + @('"' + $filePath + '"')
    $proc = Start-Process -FilePath $editorExe -ArgumentList $argList -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw 'editor exited with an error' }

    # A newly created file that is still empty is treated as unchanged.
    $unchanged = $newFile -and (Get-Item -LiteralPath $File).Length -eq 0
    if (-not $unchanged) {
        & git add -- $File
        if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
        & git diff --cached --quiet
        $unchanged = ($LASTEXITCODE -eq 0)
    }
    if ($unchanged) {
        Write-Host "No changes made to $File; nothing to commit."
        $onExit = 'remove'
        $exitCode = 0
    } else {
        if (-not $Message) {
            $Message = Read-Answer "Commit message [Update $File]"
            if (-not $Message) { $Message = "Update $File" }
        }

        # Pass the message via a file so that quotes and special characters are safe.
        $msgFile = Join-Path $tmpDir '.git/UPDATER_COMMIT_MSG'
        [IO.File]::WriteAllText($msgFile, $Message + "`n", (New-Object Text.UTF8Encoding $false))
        & git commit -F $msgFile
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }

        & git push origin HEAD
        if ($LASTEXITCODE -ne 0) { throw 'git push failed' }

        $pushed = $true
        $onExit = 'remove'
        $exitCode = 0
    }
} catch {
    $errorText = $_.Exception.Message
} finally {
    if ($inTmpDir) { Pop-Location }
    if ($errorText) {
        [Console]::Error.WriteLine("Error: $errorText")
    } elseif ($exitCode -ne 0) {
        # Reached only if interrupted (e.g. Ctrl+C) before completion.
        $errorText = 'interrupted'
        [Console]::Error.WriteLine('Error: interrupted')
    }
    if ($onExit -eq 'remove') {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $tmpDir) {
            [Console]::Error.WriteLine("Warning: could not remove $tmpDir")
            $exitCode = 1
        } elseif ($pushed) {
            Write-Host 'Changes pushed successfully; temporary clone removed.'
        }
    } else {
        [Console]::Error.WriteLine("Temporary clone left in: $tmpDir")
    }
}

exit $exitCode
