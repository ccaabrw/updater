@echo off
rem
rem update.bat - Make a shallow clone of a git repository in a temporary
rem directory, let the user edit a file, then commit and push the change
rem back to the source repository. The temporary clone is removed if all
rem steps succeed; on error it is kept so that the work is not lost.
rem
rem Usage: update.bat [-b branch] [-m message] ^<repository^> ^<file^>
rem
rem   repository  URL or path of the existing git repository
rem   file        path of the file to edit, relative to the repository root
rem   -b branch   branch to clone and push to (default: remote default branch)
rem   -m message  commit message (default: prompt for one)
rem
rem The editor is taken from %EDITOR%, falling back to notepad.

setlocal EnableExtensions DisableDelayedExpansion

set "BRANCH="
set "MESSAGE="
set "REPO="
set "FILE="

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="-b" (
    if "%~2"=="" goto usage
    set "BRANCH=%~2"
    shift
    shift
    goto parse
)
if /i "%~1"=="-m" (
    if "%~2"=="" goto usage
    set "MESSAGE=%~2"
    shift
    shift
    goto parse
)
if /i "%~1"=="-h" goto usage
if /i "%~1"=="/?" goto usage
if not defined REPO (
    set "REPO=%~1"
    shift
    goto parse
)
if not defined FILE (
    set "FILE=%~1"
    shift
    goto parse
)
goto usage

:parsed
if not defined REPO goto usage
if not defined FILE goto usage

where git >nul 2>&1
if errorlevel 1 (
    echo Error: git is not installed or not on PATH 1>&2
    exit /b 1
)

rem A local path must be given as a file:// URL for --depth to be honoured.
if exist "%REPO%\" (
    for %%I in ("%REPO%") do set "REPO=%%~fI"
    call set "REPO=file:///%%REPO:\=/%%"
)

rem Git uses forward slashes; cmd built-ins need backslashes.
set "FILE=%FILE:\=/%"
set "WINFILE=%FILE:/=\%"

:mktemp
set "TMPDIR=%TEMP%\updater-%RANDOM%%RANDOM%"
if exist "%TMPDIR%" goto mktemp
mkdir "%TMPDIR%" || (
    echo Error: could not create temporary directory 1>&2
    exit /b 1
)

echo Cloning %REPO% into %TMPDIR% ...
if defined BRANCH (
    git clone --depth 1 --branch "%BRANCH%" -- "%REPO%" "%TMPDIR%"
) else (
    git clone --depth 1 -- "%REPO%" "%TMPDIR%"
)
if errorlevel 1 (
    rmdir /s /q "%TMPDIR%" 2>nul
    echo Error: clone failed 1>&2
    exit /b 1
)

pushd "%TMPDIR%" || (
    set "ERR=cannot change to %TMPDIR%"
    goto fail
)

set "NEWFILE="
if not exist "%WINFILE%" (
    set "ANSWER="
    set /p "ANSWER=File '%FILE%' does not exist in the repository. Create it? [y/N] "
    call :create_file
    if errorlevel 2 goto declined
    if errorlevel 1 goto fail
)

if not defined EDITOR set "EDITOR=notepad"
call %EDITOR% "%WINFILE%"
if errorlevel 1 (
    set "ERR=editor exited with an error"
    goto fail
)

rem A newly created file that is still empty is treated as unchanged.
if defined NEWFILE for %%I in ("%WINFILE%") do if "%%~zI"=="0" goto nochanges

git add -- "%FILE%"
if errorlevel 1 (
    set "ERR=git add failed"
    goto fail
)

git diff --cached --quiet
if not errorlevel 1 goto nochanges

if not defined MESSAGE (
    set /p "MESSAGE=Commit message [Update %FILE%]: "
)
if not defined MESSAGE set "MESSAGE=Update %FILE%"

rem Pass the message via a file so that quotes and special characters are safe.
set "MSGFILE=%TMPDIR%\.git\UPDATER_COMMIT_MSG"
setlocal EnableDelayedExpansion
> "%MSGFILE%" echo(!MESSAGE!
endlocal
git commit -F "%MSGFILE%"
if errorlevel 1 (
    set "ERR=git commit failed"
    goto fail
)

git push origin HEAD
if errorlevel 1 (
    set "ERR=git push failed"
    goto fail
)

popd
rmdir /s /q "%TMPDIR%"
if exist "%TMPDIR%" (
    echo Warning: could not remove %TMPDIR% 1>&2
    exit /b 1
)
echo Changes pushed successfully; temporary clone removed.
exit /b 0

:nochanges
echo No changes made to %FILE%; nothing to commit.
popd
rmdir /s /q "%TMPDIR%"
exit /b 0

:declined
echo Error: file '%FILE%' not found 1>&2
popd
rmdir /s /q "%TMPDIR%"
exit /b 1

:create_file
if not defined ANSWER set "ANSWER=n"
if /i not "%ANSWER:~0,1%"=="y" (
    exit /b 2
)
for %%I in ("%WINFILE%") do if not exist "%%~dpI" mkdir "%%~dpI"
if errorlevel 1 (
    set "ERR=cannot create directory for %FILE%"
    exit /b 1
)
type nul > "%WINFILE%"
if errorlevel 1 (
    set "ERR=cannot create %FILE%"
    exit /b 1
)
set "NEWFILE=1"
exit /b 0

:fail
echo Error: %ERR% 1>&2
echo Temporary clone left in: %TMPDIR% 1>&2
popd 2>nul
exit /b 1

:usage
echo Usage: %~nx0 [-b branch] [-m message] ^<repository^> ^<file^> 1>&2
exit /b 2
