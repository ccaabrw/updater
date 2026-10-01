# updater
Scripts to update a single file in an existing git repository without
keeping a permanent working copy:

1. Make a shallow clone (`--depth 1`) of the repository in a temporary directory.
2. Open the chosen file in an editor so you can make your changes.
3. Add and commit the changes.
4. Push the commit back to the source repository.
5. If there were no errors, remove the temporary clone. If any step fails the
   clone is kept and its location printed so that no work is lost.

If the file is left unchanged, nothing is committed and the clone is removed.
If the file does not exist you are asked whether to create it.

## Unix (Linux, macOS)

```sh
./update.sh [-b branch] [-m message] <repository> <file>
```

The editor is taken from `$VISUAL`, then `$EDITOR`, falling back to `vi`.

## Windows (PowerShell)

```powershell
.\update.ps1 [-Branch branch] [-Message message] <repository> <file>
```

`-b` and `-m` are accepted as short aliases. The editor is taken from
`$env:VISUAL`, then `$env:EDITOR`, falling back to `notepad`. A full help
page is available with `Get-Help .\update.ps1 -Full`.

Works with Windows PowerShell 5.1 and PowerShell 7 (`pwsh`, which also runs
it on Linux and macOS). If the execution policy prevents running scripts,
use:

```powershell
powershell -ExecutionPolicy Bypass -File .\update.ps1 <repository> <file>
```

## Arguments

| Argument     | Description                                                      |
|--------------|------------------------------------------------------------------|
| `repository` | URL or local path of the existing git repository                 |
| `file`       | Path of the file to edit, relative to the repository root        |
| `-b branch`  | Branch to clone and push to (default: the remote default branch) |
| `-m message` | Commit message (default: prompt, suggesting `Update <file>`)     |

Example:

```sh
./update.sh -m "Fix typo" https://github.com/example/project.git docs/index.md
```

Your git user name and e-mail must be configured (`git config --global
user.name` / `user.email`) and you need push access to the repository.
