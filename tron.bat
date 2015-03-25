:: Purpose:       Runs a series of cleaners and anti-virus engines to clean up/disinfect a PC
::                  Kevin Flynn:  "Who's that guy?"
::                  Program:      "That's Tron. He fights for the User."
:: Requirements:  1. Administrator access
::                2. Safe mode is strongly recommended (though not required)
:: Author:        reddit.com/user/vocatus ( vocatus.gate@gmail.com ) // PGP key: 0x07d1490f82a211a2
:: Version:       6.0.0 + tron.bat:             Add resume function. Tron will now attempt to pick up at the last stage it successfully started if there is an interruption. You do have to log back in as the user that originally ran Tron, but assuming the Tron folder didn't move it should automatically re-launch at the last stage. Major thanks to /u/cuddlychops06 for assistance with this
::                      + stage_0_prep:sysrstr: Create System Restore checkpoint before beginning script operations. Windows client versions only, Vista and up (no Server versions)
::                      + stage_0_prep:stinger: Add McAfee Stinger tool, configured to delete infected items. Thanks to /u/upsurper
::                      ! stage_0_prep:admin:   Fix broken Administrator rights check due to minor syntax error. This has been broken since at least v2.2.1 (2014-08-21)
::                      / stage_0_prep:checks:  Move Administrator rights check before main menu and EULA screen
::                      / stage_0_prep:checks:  Move Safe Mode checks before main menu
::                      ! stage_0_prep:power:   Fix minor errors in power scheme export (Vista and up)
::                      * stage_1_tempclean:bb: Add support for -v flag to BleachBit; BleachBit now dumps list of actions if -v flag is used
::                      - stage_1_tempclean:ie: Remove redundant IE cleanup in TempFileCleanup.bat, since Tron runs this natively
::                      ! tron.bat:update:      Fix error with update checker. Was failing cert check over HTTPS. Thanks to /u/upsurper
::                      * tron.bat:logging:     Major upgrade. Now use logging functions instead of two lines per event (one to console, one to logfile). This slows down the script slightly but lets us remove over 100 lines of code, as well as simplifies troubleshooting and maintenance. Major thanks to /u/douglas_swehla
::                      / stage_4_patch:7-zip:  Send output from assoc and open-with commands to logfile instead of console
::                      * stage_4_patch:java:   Suppress unnecessary error messages about old versions not being found during previous version removal
::                      ! stage_4_patch:reader: Fix a few lines that were displaying messages instead of sending them to the log as intended
::                      * stage_5_optimize:dfg: Defrag now only runs (assuming it wasn't skipped) if the system drive is at least 5% or more fragmented
::                      * stage_6_wrap-up:      Add message explaning disk space calculations to dissuade panic about seemingly negative disk space reclaimed
::                      * stage_6_wrap-up:      Sweep misc logs in LOGPATH left from the various sub-tools into %LOGPATH%\tron_raw_logs
::
:: Usage:         Run this script in Safe Mode as an Administrator and reboot when finished. That's it.
::
::                OPTIONAL command-line flags (can be combined, none are required):
::                      -a   Automatic mode (no welcome screen or prompts; implies -e)
::                      -c   Config dump (display config. Can be used with other flags to see what
::                           WOULD happen, but script will never execute if this flag is used)
::                      -d   Dry run (run through script without executing any jobs)
::                      -e   Accept EULA (suppress disclaimer warning screen)
::                      -er  Email a report when finished. Requires you to configure SwithMailSettings.xml
::                      -gsl Generate summary logs. These specifically list removed files and programs
::                      -h   Display help text
::                      -m   Preserve OEM Metro apps (don't remove them)
::                      -o   Power off after running (overrides -r)
::                      -p   Preserve power settings (don't reset to Windows default)
::                      -r   Reboot (auto-reboot 15 seconds after completion)
::                      -sa  Skip anti-virus scans (Sophos, Vipre, MBAM)
::                      -sb  Skip de-bloat (OEM bloatware removal; implies -m)
::                      -sd  Skip defrag (force Tron to ALWAYS skip Stage 5 defrag)
::                      -se  Skip Event Log clearing
::                      -sp  Skip patches (do not patch 7-Zip, Java Runtime, Adobe Flash and Reader)
::                      -sw  Skip Windows Updates (do not attempt to run Windows Update)
::                      -v   Verbose. Show as much output as possible. NOTE: Significantly slower!
::                      -x   Self-destruct. Tron deletes itself after running and leaves logs intact
::
::                If you don't like the defaults and don't want to use the command-line, edit the variables below to change the script defaults.

::                U.S. Army Warrant Officer Corps - Quiet Professionals
SETLOCAL
@echo off


:::::::::::::::
:: VARIABLES :: ---------------- These are the defaults. Change them if you want ------------------- ::
:::::::::::::::
:: Rules for variables:
::  * NO quotes!                    (bad:  "c:\directory\path"       )
::  * NO trailing slashes on paths! (bad:   c:\directory\            )
::  * Spaces are okay               (okay:  c:\my folder\with spaces )
::  * Network paths are okay        (okay:  \\server\share name      )

:: Log and quarantine path (note: quarantine path is currently unused by Tron)
set LOGPATH=%SystemDrive%\Logs
set LOGFILE=tron.log
set QUARANTINE_PATH=%LOGPATH%\tron_quarantine


:: ! All defaults are overridden if their respective command-line flag is used
::   Note: Only command-line flags are preserved across a reboot if the script terminates unexpectedly (e.g. -gsl).
::         This means if you change the defaults here, those changes will NOT be honored if the script has to auto-resume after a reboot or crash
:: AUTORUN               (-a)   = Automatic execution (no welcome screen or prompts), implies -e
:: DRY_RUN               (-d)   = Run through script but skip all actual actions (test mode)
:: EULA_ACCEPTED         (-e)   = Accept EULA (suppress disclaimer warning screen)
:: EMAIL_REPORT          (-er)  = Email post-run report with log file. Requires you to have configured SwithMailSettings.xml prior to running
:: GENERATE_SUMMARY_LOGS (-gsl) = Generate summary logs. These specifically list removed files and programs
:: PRESERVE_METRO_APPS   (-m)   = Don't remove OEM Metro apps
:: AUTO_SHUTDOWN         (-o)   = Shutdown after the finishing. Overrides auto-reboot
:: PRESERVE_POWER_SCHEME (-p)   = Preserve active power scheme. Default is to reset power scheme to Windows defaults at the end of Tron
:: AUTO_REBOOT_DELAY     (-r)   = Post-run delay (in seconds) before rebooting. Set to 0 to disable auto-reboot
:: SKIP_ANTIVIRUS_SCANS  (-sa)  = Set to yes to skip anti-virus scanners (Sophos, Vipre, MBAM)
:: SKIP_DEBLOAT          (-sb)  = Set to yes to skip de-bloat section (OEM bloat removal). Implies -m
:: SKIP_DEFRAG           (-sd)  = Set to yes to skip defrag regardless whether the system drive is an SSD or not. When set to "no" the script will auto-detect SSDs and skip defrag if one is detected
:: SKIP_EVENT_LOG_CLEAR  (-se)  = Set to yes to skip Event Log clearing
:: SKIP_PATCHES          (-sp)  = Set to yes to skip patches (do not patch 7-Zip, Java Runtime, Adobe Flash Player and Adobe Reader)
:: SKIP_WINDOWS_UPDATES  (-sw)  = Set to yes to skip Windows Updates
:: VERBOSE               (-v)   = When possible, show as much output as possible from each program Tron calls (e.g. Sophos, Vipre, etc). NOTE: This is often much slower
:: SELF_DESTRUCT         (-x)   = Set to yes to have Tron automatically delete itself after running. Leaves logs intact
set AUTORUN=no
set DRY_RUN=no
set EULA_ACCEPTED=no
set EMAIL_REPORT=no
set GENERATE_SUMMARY_LOGS=no
set PRESERVE_METRO_APPS=no
set AUTO_SHUTDOWN=no
set PRESERVE_POWER_SCHEME=no
set AUTO_REBOOT_DELAY=0
set SKIP_ANTIVIRUS_SCANS=no
set SKIP_DEBLOAT=no
set SKIP_DEFRAG=no
set SKIP_EVENT_LOG_CLEAR=no
set SKIP_PATCHES=no
set SKIP_WINDOWS_UPDATES=no
set VERBOSE=no
set SELF_DESTRUCT=no





:: --------------------------------------------------------------------------------------------------- ::
:: ----------------- Don't edit anything below this line lest you awaken the Balrog ------------------ ::
:: --------------------------------------------------------------------------------------------------- ::





:::::::::::::::::::::
:: PREP AND CHECKS ::
:::::::::::::::::::::
cls
color 0f
set SCRIPT_VERSION=6.0.0
set SCRIPT_DATE=2015-03-25
title TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%)

:: Get the date into ISO 8601 standard date format (yyyy-mm-dd) so we can use it 
for /f %%a in ('WMIC OS GET LocalDateTime ^| find "."') DO set DTS=%%a
set CUR_DATE=%DTS:~0,4%-%DTS:~4,2%-%DTS:~6,2%

:: Initialize script-internal variables. Most of these get clobbered later so don't change them here
set CONFIG_DUMP=no
set REPO_URL=https://www.bmrf.org/repos/tron
set REPO_BTSYNC_KEY=BYQYYECDOJPXYA2ZNUDWDN34O2GJHBM47
set REPO_SCRIPT_DATE=0
set REPO_SCRIPT_VERSION=0
set HELP=no
set TARGET_METRO=no
set FREE_SPACE_AFTER=0
set FREE_SPACE_BEFORE=0
set FREE_SPACE_SAVED=0
set UNICORN_POWER_MODE=off
set SAFE_MODE=no
if /i "%SAFEBOOT_OPTION%"=="MINIMAL" set SAFE_MODE=yes
if /i "%SAFEBOOT_OPTION%"=="NETWORK" set SAFE_MODE=yes
:: Stuff related to resuming from an interrupted run
set RESUME_STAGE=0
set RESUME_FLAGS=0
set RESUME_DETECTED=no
reg query HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce\ /v "tron_resume" >nul 2>&1
if %ERRORLEVEL%==0 set RESUME_DETECTED=yes
if /i "%1"=="-resume" set RESUME_DETECTED=yes


:: Get in the correct drive (~d0). This is sometimes needed when running from a thumb drive
%~d0 2>NUL
:: Get in the correct path (~dp0). This is useful if we start from a network share, it converts CWD to a drive letter
pushd %~dp0 2>NUL



:: PREP JOB: Parse command-line arguments
for %%i in (%*) do (
	if /i %%i==-a set AUTORUN=yes
	if /i %%i==-c set CONFIG_DUMP=yes
	if /i %%i==-d set DRY_RUN=yes
	if /i %%i==-e set EULA_ACCEPTED=yes
	if /i %%i==-er set EMAIL_REPORT=yes
	if /i %%i==-gsl set GENERATE_SUMMARY_LOGS=yes
	if /i %%i==-h set HELP=yes
	if /i %%i==-m set PRESERVE_METRO_APPS=yes
	if /i %%i==-o set AUTO_SHUTDOWN=yes
	if /i %%i==-p set PRESERVE_POWER_SCHEME=yes
	if /i %%i==-r set AUTO_REBOOT_DELAY=15
	if /i %%i==-sa set SKIP_ANTIVIRUS_SCANS=yes
	if /i %%i==-sb set SKIP_DEBLOAT=yes
	if /i %%i==-sd set SKIP_DEFRAG=yes
	if /i %%i==-se set SKIP_EVENT_LOG_CLEAR=yes
	if /i %%i==-sp set SKIP_PATCHES=yes
	if /i %%i==-sw set SKIP_WINDOWS_UPDATES=yes
	if /i %%i==-v set VERBOSE=yes
	if /i %%i==-x set SELF_DESTRUCT=yes
	if %%i==-UPM set UNICORN_POWER_MODE=on
	)


:: PREP JOB: Execute help if requested
if /i %HELP%==yes (
	::cls
	echo. 
	echo  Tron v%SCRIPT_VERSION% ^(%SCRIPT_DATE%^)
	echo  Author: vocatus on reddit.com/r/TronScript
	echo.
	echo   Usage: %0% ^[-a -c -d -e -er -gsl -m -o -p -r -sa -sb -sd -se -sp -sw -v -x^] ^| ^[-h^]
	echo.
	echo   Optional flags ^(can be combined^):
	echo    -a   Automatic mode ^(no welcome screen or prompts; implies -e^)
 	echo    -c   Config dump ^(display config. Can be used with other flags to see what
	echo         WOULD happen, but script will never execute if this flag is used^)
	echo    -d   Dry run ^(run through script but don't execute any jobs^)
	echo    -e   Accept EULA ^(suppress disclaimer warning screen^)
	echo    -er  Email a report when finished. Requires you to configure SwithMailSettings.xml
	echo    -gsl Generate summary logs. These specifically list removed files and programs
	echo    -m   Preserve OEM Metro apps ^(don't remove them^)
	echo    -o   Power off after running ^(overrides -r^)
	echo    -p   Preserve power settings ^(don't reset to Windows default^)
	echo    -r   Reboot automatically ^(auto-reboot 15 seconds after completion^)
	echo    -sa  Skip anti-virus scans ^(Sophos, Vipre, MBAM^)
	echo    -sb  Skip de-bloat ^(OEM bloatware removal; implies -m^)
	echo    -sd  Skip defrag ^(force Tron to ALWAYS skip Stage 5 defrag^)
	echo    -se  Skip Event Log clearing
	echo    -sp  Skip patches ^(do not patch 7-Zip, Java Runtime, Adobe Flash or Reader^)
	echo    -sw  Skip Windows Updates ^(do not attempt to run Windows Update^)
	echo    -v   Verbose. Show as much output as possible. NOTE: Significantly slower!
	echo    -x   Self-destruct. Tron deletes itself after running and leaves logs intact
 	echo.
	echo   Misc flags ^(must be used alone^)
	echo    -h   Display this help text
	echo.
	exit /b 0
	)


:: PREP JOB: Get in the resources sub-directory. We'll be here for the rest of the script
pushd resources


:: PREP JOB: Force WMIC location in case the system PATH is messed up
set WMIC=%SystemRoot%\system32\wbem\wmic.exe


:: PREP JOB: Detect the version of Windows we're on. This determines a few things later in the script, such as which versions of SFC and powercfg.exe we run, as well as whether or not to attempt removal of Windows 8/8.1 metro apps
set WIN_VER=undetected
for /f "tokens=3*" %%i IN ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName ^| Find "ProductName"') DO set WIN_VER=%%i %%j


:: PREP JOB: Detect Solid State hard drives (determines if post-run defrag executes or not)
:: Basically we use a trick to set the global SSD_DETECTED variable outside of the setlocal block by stacking it on the same line so it gets executed along with ENDLOCAL
:: Big time thanks to reddit.com/user/Suddenly_Engineer and reddit.com/user/Aberu for helping with this
set SSD_DETECTED=no
SETLOCAL ENABLEDELAYEDEXPANSION
for /f "tokens=1" %%i in ('stage_5_optimize\defrag\smartctl.exe --scan') do (
	stage_5_optimize\defrag\smartctl.exe %%i -a | find /i "Solid State" >NUL
	if "!ERRORLEVEL!"=="0" ENDLOCAL DISABLEDELAYEDEXPANSION && set SSD_DETECTED=yes&& goto freespace_check
	)
for /f "tokens=1" %%i in ('stage_5_optimize\defrag\smartctl.exe --scan') do (
	stage_5_optimize\defrag\smartctl.exe %%i -a | find /i "SSD" >NUL
	if "!ERRORLEVEL!"=="0" ENDLOCAL DISABLEDELAYEDEXPANSION && set SSD_DETECTED=yes&& goto freespace_check
	)
for /f "tokens=1" %%i in ('stage_5_optimize\defrag\smartctl.exe --scan') do (
	stage_5_optimize\defrag\smartctl.exe %%i -a | find /i "RAID" >NUL
	if "!ERRORLEVEL!"=="0" ENDLOCAL DISABLEDELAYEDEXPANSION && set SSD_DETECTED=yes&& goto freespace_check
	)
for /f "tokens=1" %%i in ('stage_5_optimize\defrag\smartctl.exe --scan') do (
	stage_5_optimize\defrag\smartctl.exe %%i -a | find /i "SandForce" >NUL
	if "!ERRORLEVEL!"=="0" ENDLOCAL DISABLEDELAYEDEXPANSION && set SSD_DETECTED=yes&& goto freespace_check
	)
ENDLOCAL DISABLEDELAYEDEXPANSION


:: PREP JOB: Get free space on the system drive and stash it for comparison later
:: Thanks to Stack Overflow user Aacini in this post: http://stackoverflow.com/a/20392479/1347428
:freespace_check
for /F "tokens=2 delims=:" %%a in ('fsutil volume diskfree %SystemDrive% ^| find /i "avail free"') do set bytes=%%a
:: GB version
::set /A FREE_SPACE_BEFORE=%bytes:~0,-3%/1024*1000/1024/1024
:: MB version
set /A FREE_SPACE_BEFORE=%bytes:~0,-3%/1024*1000/1024



:: PREP JOB: Check if we're resuming from a failed or incomplete previous run (often caused by forced reboots in stage_3_de-bloat)
:: Populate what stage we were on as well as what CLI flags were used
if /i %RESUME_DETECTED%==yes (
	set /p RESUME_STAGE=<tron_stage.txt 2>NUL
	set /p RESUME_FLAGS=<tron_flags.txt 2>NUL
)	
if /i %RESUME_DETECTED%==yes (
	for %%i in (%RESUME_FLAGS%) do (
		if /i %%i==-a set AUTORUN=yes
		if /i %%i==-c set CONFIG_DUMP=yes
		if /i %%i==-d set DRY_RUN=yes
		if /i %%i==-e set EULA_ACCEPTED=yes
		if /i %%i==-er set EMAIL_REPORT=yes
		if /i %%i==-gsl set GENERATE_SUMMARY_LOGS=yes
		if /i %%i==-h set HELP=yes
		if /i %%i==-m set PRESERVE_METRO_APPS=yes
		if /i %%i==-o set AUTO_SHUTDOWN=yes
		if /i %%i==-p set PRESERVE_POWER_SCHEME=yes
		if /i %%i==-r set AUTO_REBOOT_DELAY=15
		if /i %%i==-sa set SKIP_ANTIVIRUS_SCANS=yes
		if /i %%i==-sb set SKIP_DEBLOAT=yes
		if /i %%i==-sd set SKIP_DEFRAG=yes
		if /i %%i==-se set SKIP_EVENT_LOG_CLEAR=yes
		if /i %%i==-sp set SKIP_PATCHES=yes
		if /i %%i==-sw set SKIP_WINDOWS_UPDATES=yes
		if /i %%i==-v set VERBOSE=yes
		if /i %%i==-x set SELF_DESTRUCT=yes
		if %%i==-UPM set UNICORN_POWER_MODE=on
	)
)
if /i %RESUME_DETECTED%==yes (
	:: Notify and jump
	call :log_heading_alert Incomplete run detected. Resuming at %RESUME_STAGE% using flags "%RESUME_FLAGS%"...
	:: Reset the RunOnce flag in case we get interrupted again
	reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /f /v "tron_resume" /t REG_SZ /d "%~dp0tron.bat %-resume" >NUL
	goto %RESUME_STAGE%
)

	
:: PREP JOB: Re-enable the standard "F8" key functionality for choosing bootup options (Microsoft disables it by default starting in Windows 8 and up)
:: Read WIN_VER and run the scan if we're on some derivative of 8. We don't need to check for Server 2012 because it's set to "legacy" by default.
if "%WIN_VER:~0,9%"=="Windows 8" (
	bcdedit /set {default} bootmenupolicy legacy
	)


::::::::::::::::::
:: UPDATE CHECK ::
::::::::::::::::::
:: Skip this job if we're doing a dry run or if AUTORUN is set
if /i %DRY_RUN%==yes goto skip_update_check
if /i %AUTORUN%==yes goto skip_update_check
:: Use wget to fetch sha256sums.txt from the repo and parse through it. Extract latest version number and release date from last line (which is always the latest release)
stage_0_prep\check_update\wget.exe --no-check-certificate %REPO_URL%/sha256sums.txt -O %TEMP%\sha256sums.txt 2>NUL
:: Assuming there was no error, go ahead and extract version number into REPO_SCRIPT_VERSION, and release date into REPO_SCRIPT_DATE
if /i %ERRORLEVEL%==0 (
	for /f "tokens=1,2,3 delims= " %%a in (%TEMP%\sha256sums.txt) do set WORKING=%%b
	for /f "tokens=4 delims=,()" %%a in (%TEMP%\sha256sums.txt) do set WORKING2=%%a
	)
if /i %ERRORLEVEL%==0 (
	set REPO_SCRIPT_VERSION=%WORKING:~1,6%
	set REPO_SCRIPT_DATE=%WORKING2%
	)

:: Reset window title since wget clobbers it
title TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%)

:: Notify if an update was found
SETLOCAL ENABLEDELAYEDEXPANSION
if /i %SCRIPT_VERSION% LSS %REPO_SCRIPT_VERSION% (
	set CHOICE=y
	color 8a
	cls
	echo.
	echo  ^^! A newer version of Tron is available on the official repo.
	echo.
	echo    Your version:   %SCRIPT_VERSION% ^(%SCRIPT_DATE%^)
	echo    Latest version: %REPO_SCRIPT_VERSION% ^(%REPO_SCRIPT_DATE%^)
	echo.
	echo    Option 1: Sync directly from repo using BT Sync read-only key:
	echo     %REPO_BTSYNC_KEY%
	echo.
	echo    Option 2: Download the latest self-extracting .exe yourself:
	echo     %REPO_URL%
	echo.
	echo    Option 3: Automatically download latest .exe to the desktop
	echo              ^(This copy of Tron will self-destruct afterwards^)
	echo.
	set /p CHOICE= Auto-download latest version now? [Y/n]: 
	if !CHOICE!==y (
		color 8B
		cls
		echo.
		echo %TIME%   Downloading new version to the desktop, please wait...
		echo.
		stage_0_prep\check_update\wget.exe --no-check-certificate "%REPO_URL%/Tron v%REPO_SCRIPT_VERSION% (%REPO_SCRIPT_DATE%).exe" -O "%USERPROFILE%\Desktop\Tron v%REPO_SCRIPT_VERSION% (%REPO_SCRIPT_DATE%).exe"
		echo.
		echo %TIME%   Download finished.
		echo.
		echo %TIME%   Verifying SHA256 pack integrity, please wait...
		echo.
		stage_0_prep\check_update\hashdeep.exe -s -e -b -a -k %TEMP%\sha256sums.txt "%USERPROFILE%\Desktop\Tron v%REPO_SCRIPT_VERSION% (%REPO_SCRIPT_DATE%).exe" >NUL
		if !ERRORLEVEL!==0 (
			echo %TIME%   SHA256 pack integrity verified. The new version is on your desktop.
			echo.
			echo %TIME%   This copy of Tron will now self-destruct.
			echo.
			popd
			pause
			echo. && ENDLOCAL DISABLEDELAYEDEXPANSION && set SELF_DESTRUCT=yes&& goto self_destruct
		) else (
			color 0c
			echo %TIME% ^^! ERROR: Download FAILED the integrity check. Recommend manually
			echo                      downloading latest version. Will delete failed file and
			echo                      exit.
			echo.
			pause
			REM Clean up after ourselves
			del /f /q "%USERPROFILE%\Desktop\Tron v%REPO_SCRIPT_VERSION% (%REPO_SCRIPT_DATE%).exe"
			del /f /q %TEMP%\sha256sums.txt
			exit
		)
	)
	color 0f
)
ENDLOCAL DISABLEDELAYEDEXPANSION
:: Clean up after ourselves
if exist "%TEMP%\*sums.txt" del "%TEMP%\*sums.txt"
:skip_update_check



:: PREP JOB: Execute config dump if requested
if /i %CONFIG_DUMP%==yes (
	cls
	echo.
	echo  Tron v%SCRIPT_VERSION% ^(%SCRIPT_DATE%^) config dump
	echo.
	echo  Command-line arguments:
	echo   %*
	echo.
	echo  User-set variables:
	echo    AUTORUN:                %AUTORUN%
	echo    AUTO_REBOOT_DELAY:      %AUTO_REBOOT_DELAY%
	echo    CONFIG_DUMP:            %CONFIG_DUMP%
	echo    AUTO_SHUTDOWN:          %AUTO_SHUTDOWN%
	echo    DRY_RUN:                %DRY_RUN%
	echo    EMAIL_REPORT:           %EMAIL_REPORT%
	echo    EULA_ACCEPTED:          %EULA_ACCEPTED%
	echo    GENERATE_SUMMARY_LOGS:  %GENERATE_SUMMARY_LOGS%
	echo    LOGPATH:                %LOGPATH%
	echo    LOGFILE:                %LOGFILE%
	echo    PRESERVE_METRO_APPS:    %PRESERVE_METRO_APPS%
	echo    PRESERVE_POWER_SCHEME:  %PRESERVE_POWER_SCHEME%
	echo    QUARANTINE_PATH:        %QUARANTINE_PATH%
	echo    SELF_DESTRUCT:          %SELF_DESTRUCT%
	echo    SKIP_ANTIVIRUS_SCANS:   %SKIP_ANTIVIRUS_SCANS%
	echo    SKIP_DEBLOAT:           %SKIP_DEBLOAT%
	echo    SKIP_DEFRAG:            %SKIP_DEFRAG%
	echo    SKIP_EVENT_LOG_CLEAR:   %SKIP_EVENT_LOG_CLEAR%
	echo    SKIP_PATCHES:           %SKIP_PATCHES%
	echo    SKIP_WINDOWS_UPDATES:   %SKIP_WINDOWS_UPDATES%
	echo    UNICORN_POWER_MODE:     %UNICORN_POWER_MODE%
	echo    VERBOSE:                %VERBOSE%
	echo.
	echo  Script-internal variables:
	echo    CUR_DATE:               %CUR_DATE%
	echo    DTS:                    %DTS%
	echo    FREE_SPACE_AFTER:       %FREE_SPACE_AFTER%
	echo    FREE_SPACE_BEFORE:      %FREE_SPACE_BEFORE%
	echo    FREE_SPACE_SAVED:       %FREE_SPACE_SAVED%
	echo    HELP:                   %HELP%
	echo    SAFE_MODE:              %SAFE_MODE%
	echo    SAFEBOOT_OPTION:        %SAFEBOOT_OPTION%
	echo    SSD_DETECTED:           %SSD_DETECTED% 
	echo    TEMP:                   %TEMP%
	echo    TIME:                   %TIME%
	echo    PROCESSOR_ARCHITECTURE: %PROCESSOR_ARCHITECTURE%
	echo    REPO_BTSYNC_KEY:        %REPO_BTSYNC_KEY%
	echo    REPO_URL:               %REPO_URL%
	echo    REPO_SCRIPT_VERSION:    %REPO_SCRIPT_VERSION%
	echo    REPO_SCRIPT_DATE:       %REPO_SCRIPT_DATE%
	echo    RESUME_DETECTED:        %RESUME_DETECTED%
	echo    RESUME_FLAGS:           %RESUME_FLAGS%
	echo    RESUME_STAGE:           %RESUME_STAGE%
	echo    SCRIPT_VERSION:         %SCRIPT_VERSION%
	echo    SCRIPT_DATE:            %SCRIPT_DATE%
	:: We need this set/endlocal pair because on Vista the OS name has "(TM)" in it, which breaks the script. Sigh
	SETLOCAL ENABLEDELAYEDEXPANSION
	echo    WIN_VER:                !WIN_VER!
	ENDLOCAL DISABLEDELAYEDEXPANSION
	echo    WMIC:                   %WMIC%
	echo.
	exit /b 0
	)


:: PREP JOB: Act on autorun flag. Skips safe mode checks, admin rights check, and EULA check. I assume if you use the auto flag (-a) you know what you're doing
if /i %AUTORUN%==yes goto execute_jobs


::::::::::::::::::::::::
:: ADMIN RIGHTS CHECK ::
::::::::::::::::::::::::
:: We skip this check if we're in Safe Mode because Safe Mode command prompt always starts with Admin rights
SETLOCAL ENABLEDELAYEDEXPANSION
if /i not "%SAFE_MODE%"=="yes" (
	fsutil dirty query %systemdrive% >NUL
	:: Previous method
	::net session >nul 2>&1
	if /i not !ERRORLEVEL!==0 (
		color cf
		cls
		echo.
		echo  ERROR
		echo.
		echo  Tron doesn't think it is running as an Administrator.
		echo  Tron MUST be run with full Administrator rights to 
		echo  function correctly.
		echo.
		echo  Close this window and re-run Tron as an Administrator.
		echo  ^(right-click Tron.bat and click "Run as Administrator"^)
		echo.
		pause
		exit /b 1
	)
)
SETLOCAL DISABLEDELAYEDEXPANSION


:: PREP JOB: Display the annoying disclaimer screen. Sigh
cls
SETLOCAL ENABLEDELAYEDEXPANSION
if /i not %EULA_ACCEPTED%==yes (
	color CF
	echo  ************************** ANNOYING DISCLAIMER **************************
	echo  * NOTE^^! By running Tron you accept COMPLETE responsibility for ANYTHING *
	echo  * that happens. Although the chance of something bad happening due to   *
	echo  * Tron is pretty remote, it's always a possibility, and Tron has ZERO   *
	echo  * WARRANTY for ANY purpose. READ THE INSTRUCTIONS and understand what   *
	echo  * Tron does, because you run it AT YOUR OWN RISK.                       *
	echo  *                                                                       *
	echo  * Tron.bat and the supporting code and scripts I've written are free    *
	echo  * and open-source under the MIT License. All 3rd-party tools Tron calls *
	echo  * ^(MBAM, TDSSK, etc^) are bound by their respective licenses. It is      *
	echo  * YOUR RESPONSIBILITY to determine if you have the rights to use these  *
	echo  * tools in whatever environment you're in.                              *
	echo  *                                                                       *
	echo  * BOTTOM LINE: there is NO WARRANTY, you are ON YOUR OWN, and anything  *
	echo  * that happens, good or bad, is YOUR RESPONSIBILITY.                    *
	echo  *************************************************************************
	echo.
	echo  Type I AGREE ^(all caps^) to accept this agreement and go to the main menu
	echo  or press ctrl^+c to cancel.
	echo.
	:eula_prompt
	set /p CHOICE= Response: 
	if not "!CHOICE!"=="I AGREE" echo You must type I AGREE to continue&& goto eula_prompt
	color 0f
	)
ENDLOCAL DISABLEDELAYEDEXPANSION


::::::::::::::::::::::
:: SAFE MODE CHECKS ::
::::::::::::::::::::::
:: Check if we're in safe mode
if /i not "%SAFE_MODE%"=="yes" (
		color 0c
		cls
		echo.
		echo  WARNING
		echo.
		echo  The system is not in safe mode. Tron functions best
		echo  in "Safe Mode with Networking" in order to download
		echo  Windows and anti-virus updates.
		echo.
		echo  Tron should still run OK, but if you have infections
		echo  or problems after running, recommend booting to
		echo  "Safe Mode with Networking" and re-running.
		echo.
		pause
		cls
		)

:: Check if we have network support
if /i "%SAFEBOOT_OPTION%"=="MINIMAL" (
		color 0e
		cls
		echo.
		echo  NOTE
		echo.
		echo  The system is in Safe Mode without Network support.
		echo  Tron functions best in "Safe Mode with Networking" in
		echo  order to download Windows and anti-virus updates.
		echo.
		echo  Tron will still function, but rebooting to "Safe Mode
		echo  with Networking" is recommended.
		echo.
		pause
		cls
		)


:: PREP JOB: UPM detection circuit
if /i %UNICORN_POWER_MODE%==on (color DF) else (color 0f)


::::::::::::::::::::
:: WELCOME SCREEN ::
::::::::::::::::::::
cls
echo  **********************  TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%)  *********************
echo  * Script to automate a series of cleanup/disinfection tools           *
echo  * Author: vocatus on reddit.com/r/TronScript                          *
echo  *                                                                     *
echo  * Stage:        Tools:                                                *
echo  *  0 Prep:      Create SysRestore point/Rkill/ProcessKiller/Stinger/  *
echo  *               TDSSKiller/registry backup/clean oldest VSS set       *
echo  *  1 TempClean: TempFileClean/BleachBit/CCleaner/IE ^& EvtLogs clean   *
echo  *  2 De-bloat:  Remove OEM bloatware, remove Metro bloatware          *
echo  *  3 Disinfect: RogueKiller/Sophos/Vipre/MBAM/DISM repair/SFC scan    *
echo  *  4 Patch:     Update 7-Zip/Java/Flash/Windows, reset DISM base      *
echo  *  5 Optimize:  chkdsk/defrag %SystemDrive% (mechanical only, SSDs skipped)      *
echo  *  6 Wrap-up:   collect misc logs, send email report (if requested)   *
echo  *                                                                     *
echo  * \resources\stage_7_manual_tools contains additional tools which may *
echo  * be run manually if necessary.                                       *
echo  ***********************************************************************
:: So ugly
echo  Current settings (run tron.bat -c to dump full config):
echo    Log location:            %LOGPATH%\%LOGFILE%
if "%AUTO_REBOOT_DELAY%"=="0" (echo    Auto-reboot delay:       disabled) else (echo    Auto-reboot delay:      %AUTO_REBOOT_DELAY% seconds)
if "%SSD_DETECTED%"=="yes" (echo    SSD detected?            %SSD_DETECTED% ^(defrag skipped^) ) else (echo    SSD detected?            %SSD_DETECTED%)
if "%SAFE_MODE%"=="no" (
		echo    Safe mode?               %SAFE_MODE% ^(not ideal^)
	) else (
		if "%SAFEBOOT_OPTION%"=="MINIMAL" echo    Safe mode?               %SAFE_MODE%, without Networking
		if "%SAFEBOOT_OPTION%"=="NETWORK" echo    Safe mode?               %SAFE_MODE%, with Networking ^(ideal^)
	)
if /i not "%SKIP_DEFRAG%"=="no" (
	echo  ! SKIP_DEFRAG set^; skipping stage 5 defrag
	echo    Runtime estimate:        4-6 hours
	goto welcome_screen_trailer
	)
if "%SSD_DETECTED%"=="yes" (echo    Runtime estimate:        4-6 hours) else (echo    Runtime estimate:        7-9 hours)
if /i %DRY_RUN%==yes echo  ! DRY_RUN set; will not execute any jobs
if /i %UNICORN_POWER_MODE%==on echo  !! UNICORN POWER MODE ACTIVATED !!
echo.
:welcome_screen_trailer
pause


::::::::::::::::::::::::
:: EMAIL CONFIG CHECK ::
::::::::::::::::::::::::
:: If -er flag was used or EMAIL_REPORT was set to yes, check for a correctly configured SwithMailSettings.xml
SETLOCAL ENABLEDELAYEDEXPANSION
if /i %EMAIL_REPORT%==yes (
	findstr /i "YOUR-EMAIL-ADDRESS" stage_6_wrap-up\email_report\SwithMailSettings.xml >NUL
	if !ERRORLEVEL!==0 (
		color cf
		cls
		echo.
		echo  ERROR
		echo.
		echo  You requested an email report ^(used the -er flag or set
		echo  the EMAIL_REPORT variable to "yes"^) but didn't configure
		echo  the settings file with your information. Update the following
		echo  file with your SMTP username, password, etc:
		echo.
		echo  \resources\stage_6_wrap-up\email_report\SwithMailSettings.xml
		echo.
		echo  Alternatively you can run SwithMail.exe to have the GUI generate
		echo  a config file for you.
		echo.
		pause
	)
)
ENDLOCAL DISABLEDELAYEDEXPANSION



::::::::::::::::::
:: EXECUTE JOBS ::
::::::::::::::::::
:execute_jobs

:: Make log file and directories if they don't already exist
if /i not exist "%LOGPATH%" mkdir "%LOGPATH%"
if /i not exist "%LOGPATH%\tron_event_log_backups" mkdir "%LOGPATH%\tron_event_log_backups"
if /i not exist "%LOGPATH%\tron_raw_logs" mkdir "%LOGPATH%\tron_raw_logs"
if /i not exist "%LOGPATH%\tron_summary_logs" mkdir "%LOGPATH%\tron_summary_logs"

:: If we're resuming from a script interruption we don't want to wipe the log, so check for that here
if /i %RESUME_DETECTED%==no echo. > "%LOGPATH%\%LOGFILE%"


:: Add a RunOnce entry to relaunch Tron if it gets interrupted by a reboot. This is deleted at the end of the script if nothing went wrong.
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /f /v "tron_resume" /t REG_SZ /d "%~dp0tron.bat %-resume" >nul 2>&1


:: UPM detection circuit #2
if /i %UNICORN_POWER_MODE%==on (color DF) else (color 0f)


:: Create log header
cls
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------
call :log_heading TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%), %PROCESSOR_ARCHITECTURE% architecture
echo                          Executing as "%USERDOMAIN%\%USERNAME%" on %COMPUTERNAME%>> %LOGPATH%\%LOGFILE%
echo                          Executing as "%USERDOMAIN%\%USERNAME%" on %COMPUTERNAME%
echo                          Logfile:   %LOGPATH%\%LOGFILE%>> %LOGPATH%\%LOGFILE%
echo                          Logfile:   %LOGPATH%\%LOGFILE%
echo                          Command-line flags: %*>> %LOGPATH%\%LOGFILE%
echo                          Command-line flags: %*
echo                          Safe Mode: %SAFE_MODE% %SAFEBOOT_OPTION%>> %LOGPATH%\%LOGFILE%
echo                          Safe Mode: %SAFE_MODE% %SAFEBOOT_OPTION%
echo                          Free space before Tron run: %FREE_SPACE_BEFORE% MB>> %LOGPATH%\%LOGFILE%
echo                          Free space before Tron run: %FREE_SPACE_BEFORE% MB
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------



:::::::::::::::::::
:: STAGE 0: PREP ::
:::::::::::::::::::
:stage_0_prep
:: Stamp current stage and CLI flags so we can resume if we get interrupted by a reboot
echo stage_0_prep>tron_stage.txt
echo %*> tron_flags.txt
title TRON v%SCRIPT_VERSION% [stage_0_prep]
call :log_heading stage_0_prep jobs begin...


:: JOB: Create pre-run Restore Point so we can roll the system back if anything blows up
:: Note, there is a (stupid) limitation in Windows 8 and up that will only let you create
:: one restore point every 24 hours. If you create another one, it deletes the previous one.
:: So unfortunately we can't take a before/after restore point pair. 
if /i not "%WIN_VER:~0,9%"=="Microsoft" (
	if /i not "%WIN_VER:~0,14%"=="Windows Server" (
		call :log Attempting to create pre-run Restore Point ^(Vista and up only^)...
		if /i %DRY_RUN%==no (
			powershell "Checkpoint-Computer -Description 'TRON v%SCRIPT_VERSION%: Pre-run checkpoint' | Out-Null" >> "%LOGPATH%\%LOGFILE%" 2>&1
		)
	)
)
call :log OK.


:: JOB: Get pre-Tron system state (installed programs, complete file list). Thanks to /u/Reverent for building this section
if /i %GENERATE_SUMMARY_LOGS%==yes (
call :log Summary logs requested, generating pre-run system profile...
	if /i %DRY_RUN%==no (
		:: Get list of installed programs
		stage_0_prep\log_tools\siv\siv32x.exe -save=[software]="%LOGPATH%\tron_raw_logs\installed-programs-before.txt"
		:: Get list of all files on system
		stage_0_prep\log_tools\everything\everything.exe -create-filelist %LOGPATH%\tron_raw_logs\filelist-before.txt %SystemDrive%
	)
call :log Done.
)



:: JOB: rkill
call :log Launch job 'rkill'...
if /i %DRY_RUN%==no (
	stage_0_prep\rkill\explorer.exe -s -l "%TEMP%\tron_rkill.log"
	type "%TEMP%\tron_rkill.log" >> "%LOGPATH%\%LOGFILE%" 2>NUL
	del "%TEMP%\tron_rkill.log" 2>NUL
	if exist "%HOMEDRIVE%\%HOMEPATH%\Desktop\Rkill.txt" del "%HOMEDRIVE%\%HOMEPATH%\Desktop\Rkill.txt" 2>NUL
	)
call :log Done.


:: JOB: ProcessKiller
call :log Launch Job 'ProcessKiller'...
if /i %DRY_RUN%==no stage_0_prep\processkiller\ProcessKiller.exe
call :log Done.


:: JOB: Check WMI and repair if necessary
call :log Checking WMI...
if /i %DRY_RUN%==yes goto skip_repair_wmi

%WMIC% timezone >NUL
if /i not %ERRORLEVEL%==0 (
    call :log_alert WMI appears to be broken. Running WMI repair. This might take a minute, please be patient...
    net stop winmgmt
    pushd %SystemRoot%\system32\wbem
    for %%i in (*.dll) do RegSvr32 -s %%i
    :: Kill this random window that pops up
    tskill wbemtest /a 2>NUL
    scrcons.exe /RegServer
    unsecapp.exe /RegServer
    start "" wbemtest.exe /RegServer
    tskill wbemtest /a 2>NUL
    tskill wbemtest /a 2>NUL
    :: winmgmt.exe /resetrepository       -- optional; force full rebuild instead of repair like the line below this. Enable if you're feeling REAAAALLY crazy
    winmgmt.exe /salvagerepository /resyncperf
    wmiadap.exe /RegServer
    wmiapsrv.exe /RegServer
    wmiprvse.exe /RegServer
    :: Get the 64-bit versions if they exist
	if exist %SystemRoot%\SysWOW64\wbem ( 
		pushd %SystemRoot%\SysWOW64\wbem
		for %%j in (*.dll) do RegSvr32 -s %%j
		winmgmt.exe /salvagerepository /resyncperf
		wmiadap.exe /RegServer
		wmiprvse.exe /RegServer
		popd
		)
	net start winmgmt
	popd
    )

:skip_repair_wmi
call :log Done.


:: JOB: Backup registry
call :log Backing up registry to "%LOGPATH%"...
if /i %DRY_RUN%==no stage_0_prep\backup_registry\erunt.exe "%LOGPATH%\tron_registry_backup" /noconfirmdelete /noprogresswindow
call :log Done.


:: JOB: McAfee Stinger
call :log Launch job 'McAfee Stinger'...
call :log Stinger doesn't support text logs, saving HTML log to "%LOGPATH%\tron_raw_logs\"
if /i %DRY_RUN%==no (
	start /wait stage_0_prep\mcafee_stinger\stinger32.exe --GO --SILENT --PROGRAM --REPORTPATH="%LOGPATH%\tron_raw_logs" --DELETE
	)
call :log Done.


:: JOB: TDSS Killer
call :log Launch job 'TDSSKiller'...
if /i %DRY_RUN%==no (
	"stage_0_prep\tdss_killer\TDSSKiller v3.0.0.42.exe" -l %TEMP%\tdsskiller.log -silent -tdlfs -dcexact -accepteula -accepteulaksn
	:: Copy TDSSKiller log into the main Tron log
	type "%TEMP%\tdsskiller.log" >> "%LOGPATH%\%LOGFILE%"
	del "%TEMP%\tdsskiller.log" 2>NUL
	)
call :log Done.


:: JOB: Purge oldest shadow copies
call :log Purging oldest Shadow Copy set (Win7 and up)...
:: Read 9 characters into the WIN_VER variable. Only versions of Windows older than Vista had "Microsoft" as the first part of their title,
:: so if we don't find "Microsoft" in the first 9 characters we can safely assume we're not on XP/2k3
:: Then we check for Vista, because vssadmin on Vista doesn't support deleting old copies. Sigh. 
if /i not "%WIN_VER:~0,9%"=="Microsoft" (
	if /i not "%WIN_VER:~0,9%"=="Windows V" (
		if /i %DRY_RUN%==no (
			:: Force allow us to start VSS service in Safe Mode
			reg add "HKLM\SYSTEM\CurrentControlSet\Control\SafeBoot\%SAFEBOOT_OPTION%\VSS" /ve /t reg_sz /d Service /f >nul 2>&1
			net start VSS >nul 2>&1
			vssadmin delete shadows /for=%SystemDrive% /oldest /quiet >nul 2>&1
			)
		)
	)
call :log Done.


:: JOB: Disable sleep mode
call :log Disabling Sleep mode...
if /i %DRY_RUN%==yes goto skip_disable_sleep

:: Export the current power scheme to a file. Thanks to reddit.com/user/GetOnMyAmazingHorse
call :log Backing up power scheme and switching to Always On...
SETLOCAL ENABLEDELAYEDEXPANSION
:: Windows XP/2003 version
if /i "%WIN_VER:~0,9%"=="Microsoft" (
	REM Extract the line containing the current power GUID
	for /f "delims=^T" %%i in ('%WINDIR%\system32\powercfg.exe -query ^| find /i "Name"') do (set t=%%i)
	REM Parse out just the name and stash it in a variable
	set POWER_SCHEME=!t:~27!
	REM Export the power scheme based on this GUID
	%WINDIR%\system32\powercfg.exe /EXPORT "!POWER_SCHEME!" /FILE "%LOGPATH%\tron_power_config_backup.pow"
	REM Set the "High Performance" scheme active
	%WINDIR%\system32\powercfg.exe /SETACTIVE "Always On"
) else (
	REM All other versions of Windows
	REM Extract the line containing the current power GUID
	for /f "delims=" %%i in ('%WINDIR%\system32\powercfg.exe -list ^| find "*"') do (set t=%%i)
	REM Parse out the GUID and stash it in a variable
	set POWER_SCHEME=!t:~19,36!
	REM Export the power scheme based on this GUID
	%WINDIR%\system32\powercfg.exe -EXPORT "%LOGPATH%\tron_power_config_backup.pow" !POWER_SCHEME! 2>NUL
	REM Set the "High Performance" scheme active
	%WINDIR%\system32\powercfg.exe -SETACTIVE 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
	REM We use exclamation points around WIN_VER here because "Vista (TM) Home Premium" has parenthesis in the name which breaks the script. Sigh
	echo %CUR_DATE% %TIME%    !WIN_VER! detected, disabling system sleep on laptop lid close...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%    !WIN_VER! detected, disabling system sleep on laptop lid close...
	REM Disable system sleep when laptop lid closes. Thanks to /u/ComputersByte for the suggestion
	REM This line looks bonkers, but it's fairly straight-forward. There are three GUIDs and a setting, as follows:
	REM	1st: Master GUID of the "High Performance" power scheme
	REM	2nd: Subgroup GUID of the "Power buttons and lid" category
	REM	3rd: Specific GUID for the "Lid close action" power setting
	REM	4th: Action code for "Do nothing"
	%WINDIR%\system32\powercfg.exe -SETACVALUEINDEX 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 000 2>NUL
	)

:: This cheats a little bit by stacking the set command on the same line as the endlocal so it executes immediately after ENDLOCAL but before the variable gets wiped out by the endlocal. Kind of a little trick to get a SETLOCAL-internal variable exported to a global script-wide variable.
:: We need the POWER_SCHEME GUID for later when we re-import everything
ENDLOCAL DISABLEDELAYEDEXPANSION && set POWER_SCHEME=%POWER_SCHEME%

:skip_disable_sleep
call :log Done.


:: JOB: Reduce SysRestore space
call :log Reducing max allowed System Restore space to 7%% of disk...
if /i %DRY_RUN%==no (
	%SystemRoot%\System32\reg.exe add "\\%COMPUTERNAME%\HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v DiskPercent /t REG_DWORD /d 00000007 /f>> "%LOGPATH%\%LOGFILE%"
	%SystemRoot%\System32\reg.exe add "\\%COMPUTERNAME%\HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore\Cfg" /v DiskPercent /t REG_DWORD /d 00000007 /f>> "%LOGPATH%\%LOGFILE%"
	)
call :log Done.
call :log_heading stage_0_prep jobs complete.



::::::::::::::::::::::::
:: STAGE 1: TEMPCLEAN ::
::::::::::::::::::::::::
:stage_1_tempclean
:: Stamp current stage so we can resume if we get interrupted by a reboot
echo stage_1_tempclean>tron_stage.txt
title TRON v%SCRIPT_VERSION% [stage_1_tempclean]
call :log_heading stage_1_tempclean jobs begin...


:: JOB: Clean Internet Explorer; Windows' built-in method
call :log Launch job 'Clean Internet Explorer'...
if /i %DRY_RUN%==no rundll32.exe inetcpl.cpl,ClearMyTracksByProcess 4351
call :log Done.


:: JOB: TempFileCleanup.bat
call :log Launch job 'TempFileCleanup'...
if /i %DRY_RUN%==no call stage_1_tempclean\tempfilecleanup\TempFileCleanup.bat >> "%LOGPATH%\%LOGFILE%" 2>NUL
:: Reset window title since TempFileCleanup clobbers it
title TRON v%SCRIPT_VERSION% [stage_1_tempclean]
call :log Done.


:: JOB: CCLeaner
call :log Launch job 'CCleaner'...
if /i %DRY_RUN%==no (
	stage_1_tempclean\ccleaner\ccleaner.exe /auto>> "%LOGPATH%\%LOGFILE%" 2>NUL
	ping 127.0.0.1 -n 12 >NUL
	)
call :log Done.


:: JOB: BleachBit
call :log Launch job 'BleachBit'...
if /i %DRY_RUN%==no (
	if %VERBOSE%==yes stage_1_tempclean\bleachbit\bleachbit_console.exe --preset -p
	stage_1_tempclean\bleachbit\bleachbit_console.exe --preset -c >> "%LOGPATH%\%LOGFILE%" 2>NUL
	ping 127.0.0.1 -n 12 >NUL
	)
call :log Done.


:: JOB: USB Device Cleanup
call :log Launch job 'USB Device Cleanup'...
if /i %DRY_RUN%==no (
if /i '%PROCESSOR_ARCHITECTURE%'=='AMD64' (
	if %VERBOSE%==yes "stage_1_tempclean\usb_cleanup\DriveCleanup x64.exe" -t -n
	"stage_1_tempclean\usb_cleanup\DriveCleanup x64.exe" -n >> "%LOGPATH%\%LOGFILE%" 2>NUL
) else (
	if %VERBOSE%==yes "stage_1_tempclean\usb_cleanup\DriveCleanup x86.exe" -t -n
	"stage_1_tempclean\usb_cleanup\DriveCleanup x86.exe" -n >> "%LOGPATH%\%LOGFILE%" 2>NUL
)
call :log Done.


:: JOB: Clear Windows event logs
call :log Launch job 'Clear Windows event logs'...
if /i %SKIP_EVENT_LOG_CLEAR%==yes (
	call :log_alert SKIP_EVENT_LOG_CLEAR ^(-se^) set. Skipping Event Log clear.
	goto skip_event_log_clear
	)
call :log Saving logs to "%LOGPATH%\tron_event_log_backups" first...
:: Backup all logs first. Redirect error output to NUL (2>nul) because due to the way WMI formats lists, there is
:: a trailing blank line which messes up the last iteration of the FOR loop, but we can safely suppress errors from it
SETLOCAL ENABLEDELAYEDEXPANSION
if /i %DRY_RUN%==no for /f %%i in ('%WMIC% nteventlog where "filename like '%%'" list instance') do %WMIC% nteventlog where "filename like '%%%%i%%'" backupeventlog "%LOGPATH%\tron_event_log_backups\%%i.evt" >> "%LOGPATH%\%LOGFILE%" 2>NUL
ENDLOCAL DISABLEDELAYEDEXPANSION
call :log Backups done, now clearing...
:: Clear the logs
if /i %DRY_RUN%==no %WMIC% nteventlog where "filename like '%%'" cleareventlog >> "%LOGPATH%\%LOGFILE%"
:: Alternate Vista-and-up only method
:: if /i %DRY_RUN%==no for /f %%x in ('wevtutil el') do wevtutil cl "%%x" 2>NUL

call :log Done.
:skip_event_log_clear



:: JOB: Clear Windows Update cache
call :log Launch job 'Clear Windows Update cache'...
if /i %DRY_RUN%==no (
	:: Allow us to start the service in Safe Mode. Thanks to /u/GrizzlyWinter
	reg add "HKLM\SYSTEM\CurrentControlSet\Control\SafeBoot\%SAFEBOOT_OPTION%\WUAUSERV" /ve /t reg_sz /d Service /f >> "%LOGPATH%\%LOGFILE%" 2>&1
	net stop WUAUSERV >> "%LOGPATH%\%LOGFILE%" 2>&1
	if exist %windir%\softwaredistribution\download rmdir /s /q %windir%\softwaredistribution\download >> "%LOGPATH%\%LOGFILE%" 2>&1
	net start WUAUSERV >> "%LOGPATH%\%LOGFILE%" 2>&1
	)
call :log Done.


call :log_heading stage_1_tempclean jobs complete.



:::::::::::::::::::::::
:: STAGE 2: De-Bloat ::
:::::::::::::::::::::::
:stage_2_de-bloat
:: Stamp current stage so we can resume if we get interrupted by a reboot
echo stage_2_de-bloat>tron_stage.txt
title TRON v%SCRIPT_VERSION% [stage_2_de-bloat]
if /i %SKIP_DEBLOAT%==yes (
	call :log_heading_alert SKIP_DEBLOAT ^(-sb^) set, skipping Stage 2 jobs...
	goto skip_debloat
	)

call :log_heading stage_2_de-bloat begin...


:: JOB: Remove crapware programs, phase 1 (by name)
call :log Attempt junkware removal: Phase 1 (by name)...
call :log Customize here: \resources\stage_2_de-bloat\oem\programs_to_target.txt
:: Search through the list of programs in "programs_to_target.txt" file and uninstall them one-by-one
if /i %DRY_RUN%==no FOR /F "tokens=*" %%i in (stage_2_de-bloat\oem\programs_to_target.txt) DO echo   %%i && echo   %%i...>> "%LOGPATH%\%LOGFILE%" && %WMIC% product where "name like '%%i'" uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"
call :log Done.


:: JOB: Remove crapware programs, phase 2 (by GUID)
call :log Attempt junkware removal: Phase 2 (by GUID)...
call :log Customize here: \resources\stage_2_de-bloat\oem\programs_to_target_by_GUID.bat
if /i %DRY_RUN%==no call stage_2_de-bloat\oem\programs_to_target_by_GUID.bat >> "%LOGPATH%\%LOGFILE%" 2>&1
call :log Done.


:: JOB: Remove default Metro apps (Windows 8/8.1/2012/2012-R2 only). Thanks to https://keybase.io/exabrial
:: Read nine characters into the WIN_VER variable (starting at position 0 on the left) to check for Windows 8; 16 characters in to check for Server 2012.
:: The reason we read partially into the variable instead of comparing the whole thing is because we don't care what sub-version of 8/2012 we're on. 
:: Also I'm lazy and don't want to write ten different comparisons for all the random sub-versions MS churns out with inconsistent names.
if "%WIN_VER:~0,9%"=="Windows 8" set TARGET_METRO=yes
if "%WIN_VER:~0,18%"=="Windows Server 201" set TARGET_METRO=yes
:: Check if we're forcefully skipping Metro de-bloat. Thanks to /u/swtester for the suggestion
if %PRESERVE_METRO_APPS%==yes set TARGET_METRO=no
if /i %TARGET_METRO%==yes (
	call :log "%WIN_VER%" detected, removing OEM Metro apps...
	:: Force allowing us to start AppXSVC service in Safe Mode. AppXSVC is the MSI Installer equivalent for "apps" (vs. programs)
	if /i %DRY_RUN%==no (
		reg add "HKLM\SYSTEM\CurrentControlSet\Control\SafeBoot\%SAFEBOOT_OPTION%\AppXSVC" /ve /t reg_sz /d Service /f >nul 2>&1
		net start AppXSVC
		:: Enable scripts in PowerShell
		powershell "Set-ExecutionPolicy Unrestricted -force 2>&1 | Out-Null"
		:: Call PowerShell to run the commands
		powershell "Get-AppXProvisionedPackage -online | Remove-AppxProvisionedPackage -online 2>&1 | Out-Null"
		powershell "Get-AppxPackage -AllUsers | Remove-AppxPackage 2>&1 | Out-Null"
		)
	call :log Running DISM cleanup against unused App binaries...
	:: Thanks to reddit.com/user/nommaddave
	if /i %DRY_RUN%==no Dism /Online /Cleanup-Image /StartComponentCleanup /Logpath:"%LOGPATH%\tron_dism.log"
	call :log Done.	
)


call :log_heading stage_2_de-bloat jobs complete.
:skip_debloat



::::::::::::::::::::::::
:: STAGE 3: Disinfect ::
::::::::::::::::::::::::
:stage_3_disinfect
:: Stamp current stage so we can resume if we get interrupted by a reboot
echo stage_3_disinfect>tron_stage.txt
title TRON v%SCRIPT_VERSION% [stage_3_disinfect]
call :log_heading stage_3_disinfect jobs begin...


:: JOB: RogueKiller
call :log  Launch job 'RogueKiller' (SLOW, be patient)...
if /i %DRY_RUN%==no (
	if /i %VERBOSE%==yes echo remove| stage_3_disinfect\roguekiller\RogueKillerCMD.exe -scan remove
	if /i %VERBOSE%==no echo remove| stage_3_disinfect\roguekiller\RogueKillerCMD.exe -scan remove >> "%LOGPATH%\%LOGFILE%"
	)
call :log Done.


:: JOB: Check for -sa flag (skip antivirus scans) and skip Sophos, Vipre and MBAM if it was used
if /i %SKIP_ANTIVIRUS_SCANS%==yes (
	call :log_heading_alert SKIP_ANTIVIRUS_SCANS ^(-sa^) set. Skipping Sophos, Vipre and MBAM scans.
	goto skip_antivirus_scans
	)


:: JOB: MBAM (MalwareBytes Anti-Malware)
call :log Launch job 'Install Malwarebytes Anti-Malware'...
:: Install MBAM & remove the desktop icon
if /i %DRY_RUN%==no ( 
	"stage_3_disinfect\mbam\Malwarebytes Anti-Malware v2.1.4.1018.exe" /verysilent
	::"Malwarebytes Anti-Malware v1.75.0.1300.exe" /SP- /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /NOCANCEL
	if exist "%PUBLIC%\Desktop\Malwarebytes Anti-Malware.lnk" del "%PUBLIC%\Desktop\Malwarebytes Anti-Malware.lnk"
	if exist "%USERPROFILE%\Desktop\Malwarebytes Anti-Malware.lnk" del "%USERPROFILE%\Desktop\Malwarebytes Anti-Malware.lnk"
	if exist "%ALLUSERSPROFILE%\Desktop\Malwarebytes Anti-Malware.lnk" del "%ALLUSERSPROFILE%\Desktop\Malwarebytes Anti-Malware.lnk"

	:: Scan for and launch appropriate architecture version
	if exist "%ProgramFiles(x86)%\Malwarebytes Anti-Malware" (
		start "" "%ProgramFiles(x86)%\Malwarebytes Anti-Malware\mbam.exe"
	) else (
		start "" "%ProgramFiles%\Malwarebytes Anti-Malware\mbam.exe"
		)
)

call :log Done.
call :log_alert NOTE: You must manually click SCAN in the MBAM window!


:: JOB: Sophos Virus Remover
call :log Launch job 'Sophos Virus Removal Tool' (slow, be patient)...
call :log Scanning. Output REDUCED by default (use -v to show)...
echo.
if /i %DRY_RUN%==no (
	if exist "%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs\SophosVirusRemovalTool.log" del /f /q "%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs\SophosVirusRemovalTool.log" >nul 2>&1
	if /i %VERBOSE%==no	stage_3_disinfect\sophos_virus_remover\svrtcli.exe -yes
	if /i %VERBOSE%==yes stage_3_disinfect\sophos_virus_remover\svrtcli.exe -yes -debug
	type "%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs\SophosVirusRemovalTool.log" >> "%LOGPATH%\%LOGFILE%"
	if exist "%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs\SophosVirusRemovalTool.log" del /f /q "%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs\SophosVirusRemovalTool.log" >nul 2>&1
	)
call :log Done.


:: JOB: VIPRE Rescue
:: We have to pushd and popd here because Vipre tries to stage its definition files in the current directory
call :log Launch job 'Vipre rescue scanner' (slow, be patient)...
pushd stage_3_disinfect\vipre_rescue
call :log Scan in progress. Output hidden by default (use -v to show)...
if /i %DRY_RUN%==no ( 
	if /i %VERBOSE%==no VipreRescueScanner.exe /nolog >> "%LOGPATH%\%LOGFILE%"
	if /i %VERBOSE%==yes VipreRescueScanner.exe
	)
popd
call :log Done.

:: AV scans finished
call :log Done.
:skip_antivirus_scans


:: JOB: Check Windows Image for corruptions before running SFC (Windows 8/2012 only)
:: Thanks to /u/nomaddave
call :log Launch job 'Dism Windows image check (Win8/2012 only)'...
if /i %DRY_RUN%==yes goto skip_dism_image_check

:: Read WIN_VER and run the scan if we're on some derivative of 8 or 2012
if "%WIN_VER:~0,9%"=="Windows Server 2012" (
	Dism /Online /NoRestart /Cleanup-Image /ScanHealth /Logpath:"%LOGPATH%\tron_dism.log"
	type "%LOGPATH%\tron_dism.log" >> "%LOGPATH%\%LOGFILE%"
	del /f /q "%LOGPATH%\tron_dism.log"
	)
if "%WIN_VER:~0,9%"=="Windows 8" (
	Dism /Online /NoRestart /Cleanup-Image /ScanHealth /Logpath:"%LOGPATH%\tron_dism.log"
	type "%LOGPATH%\tron_dism.log" >> "%LOGPATH%\%LOGFILE%"
	del /f /q "%LOGPATH%\tron_dism.log"
	)

:: If we detect errors try to repair them
if /i not %ERRORLEVEL%==0 (
	if "%WIN_VER:~0,9%"=="Windows Server 2012" (
		call :log_alert DISM: Image corruption detected. Attempting repair...
		:: Add /LimitAccess flag to this command to prevent connecting to Windows Update for replacement files
		Dism /Online /NoRestart /Cleanup-Image /RestoreHealth /Logpath:"%LOGPATH%\tron_dism.log"
		type "%LOGPATH%\tron_dism.log" >> "%LOGPATH%\%LOGFILE%"
		)
	if "%WIN_VER:~0,9%"=="Windows 8" (
		call :log_alert DISM: Image corruption detected. Attempting repair...
		:: Add /LimitAccess flag to this command to prevent connecting to Windows Update for replacement files
		Dism /Online /NoRestart /Cleanup-Image /RestoreHealth /Logpath:"%LOGPATH%\tron_dism.log"
		type "%LOGPATH%\tron_dism.log" >> "%LOGPATH%\%LOGFILE%"
	) else (
		call :log DISM: No image corruption detected.
		)
	)

:skip_dism_image_check
call :log Done.


:: JOB: System File Checker (SFC) scan
call :log Launch job 'System File Checker'...
if /i %DRY_RUN%==yes goto skip_sfc
:: Basically this says "If OS is NOT XP or 2003, go ahead and run system file checker"
if /i not "%WIN_VER:~0,9%"=="Microsoft" %SystemRoot%\System32\sfc.exe /scannow
:: Dump the SFC log into the Tron log. Thanks to reddit.com/user/adminhugh
%SystemRoot%\System32\findstr.exe /c:"[SR]" %SystemRoot%\logs\cbs\cbs.log>> "%LOGPATH%\%LOGFILE%" 2>NUL
:skip_sfc
call :log Done.

call :log_heading stage_3_disinfect jobs complete.

:: Since this whole section takes a long time to run, set the date again in case we crossed over midnight during the scans.
:: This is a half-hearted fix for now. Thanks to /u/ScubaSteve for finding the bug.
FOR /f %%a in ('WMIC OS GET LocalDateTime ^| find "."') DO set DTS=%%a
set CUR_DATE=%DTS:~0,4%-%DTS:~4,2%-%DTS:~6,2%



::::::::::::::::::::::
:: STAGE 4: Patches ::
::::::::::::::::::::::
:stage_4_patch
:: Stamp current stage so we can resume if we get interrupted by a reboot
echo stage_4_patch>tron_stage.txt
title TRON v%SCRIPT_VERSION% [stage_4_patch]
call :log_heading stage_4_patch jobs begin...


:: Prep task: enable MSI installer in Safe Mode
if /i %DRY_RUN%==no (
	if not "%SAFE_MODE%"=="" reg add "HKLM\SYSTEM\CurrentControlSet\Control\SafeBoot\%SAFEBOOT_OPTION%\MSIServer" /ve /t reg_sz /d Service /f >nul 2>&1
	net start msiserver >nul 2>&1
	)
	
:: Check for skip patches (-sp) flag or variable and skip if used
if /i %SKIP_PATCHES%==yes (
	call :log_alert SKIP_PATCHES ^(-sp^) set. Skipping app patches.
	goto skip_patches
	)
	

:: JOB: 7-Zip
call :log Launch job 'Update 7-Zip'...

:: Check if we're on 32-bit Windows and run the appropriate architecture installer
if /i %DRY_RUN%==yes goto skip_7-Zip
if /i '%PROCESSOR_ARCHITECTURE%'=='x86' (
	setlocal
	call "stage_4_patch\7-Zip\v9.38\x86\7-Zip v9.38 x86.bat"
	endlocal
) else (
	setlocal
	call "stage_4_patch\7-Zip\v9.38\x64\7-Zip v9.38 x64.bat"
	endlocal
	)
:skip_7-Zip

call :log Done.


:: JOB: Adobe Flash Player
call :log Launch job 'Update Adobe Flash Player (Firefox)'...
setlocal
if /i %DRY_RUN%==no call "stage_4_patch\adobe\flash_player\firefox\Adobe Flash Player (Firefox).bat"
endlocal
call :log Done.
call :log Launch job 'Update Adobe Flash Player (IE)'...
setlocal
if /i %DRY_RUN%==no call "stage_4_patch\adobe\flash_player\internet explorer\Adobe Flash Player (IE).bat"
endlocal
call :log Done.


:: JOB: Adobe Reader
call :log Launch job 'Update Adobe Reader'...
setlocal
if /i %DRY_RUN%==no call "stage_4_patch\adobe\reader\x86\Adobe Reader.bat"
endlocal
call :log Done.


:: JOB: Java Runtime update
call :log Launch job 'Update Java Runtime Environment'...
call :log Checking for and removing outdated installations first...
if /i %DRY_RUN%==yes goto skip_jre_update
:: Okay, so all JRE runtimes (series 4-8) use product GUIDs, with certain numbers that increment with each new update (e.g. Update 25)
:: This makes it easy to catch ALL of them through liberal use of WMI wildcards ("_" is single character, "%" is any number of characters)
:: Additionally, JRE 6 introduced 64-bit runtimes, so in addition to the two-digit Update XX revision number, we also check for the architecture 
:: type, which always equals '32' or '64'. The first wildcard is the architecture, the second is the revision/update number.

:: JRE 8
:: we skip JRE 8 because the JRE 8 update script automatically removes older versions, no need to do it twice

:: JRE 7
call :log JRE 7...
%WMIC% product where "IdentifyingNumber like '{26A24AE4-039D-4CA4-87B4-2F___170__FF}'" call uninstall /nointeractive >> "%LOGPATH%\%LOGFILE%" 2>NUL

:: JRE 6
call :log JRE 6...
:: 1st line is for updates 23-xx, after 64-bit runtimes were introduced.
:: 2nd line is for updates 1-22, before Oracle released 64-bit JRE 6 runtimes
%WMIC% product where "IdentifyingNumber like '{26A24AE4-039D-4CA4-87B4-2F8__160__FF}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%" 2>NUL
%WMIC% product where "IdentifyingNumber like '{3248F0A8-6813-11D6-A77B-00B0D0160__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%" 2>NUL

:: JRE 5
call :log JRE 5...
%WMIC% product where "IdentifyingNumber like '{3248F0A8-6813-11D6-A77B-00B0D0150__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%" 2>NUL

:: JRE 4
call :log JRE 4...
%WMIC% product where "IdentifyingNumber like '{7148F0A8-6813-11D6-A77B-00B0D0142__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%" 2>NUL

call :log Done.


call :log Installing latest JRE...
:: Check if we're on 32-bit Windows and run the appropriate installer
if /i '%PROCESSOR_ARCHITECTURE%'=='x86' (
	call :log x86 architecture detected, installing x86 version...
	setlocal
	call "stage_4_patch\java\jre\8\x86\jre-8-i586.bat"
	endlocal
) else (
	call :log x64 architecture detected, installing x64 version...
	setlocal
	call "stage_4_patch\java\jre\8\x64\jre-8-x64.bat"
	endlocal
	)

:skip_jre_update
call :log Done.


:: JOB: Skip point for if -sp (skip patches) flag was used
:skip_patches


:: JOB: Windows updates
call :log Launch job 'Install Windows updates'...
if /i %DRY_RUN%==no (
	if /i %SKIP_WINDOWS_UPDATES%==no (
		wuauclt /detectnow /updatenow
		call :log Done.
	) else (
		call :log_alert SKIP_WINDOWS_UPDATES ^(-sw^) set to "%SKIP_WINDOWS_UPDATES%", skipping Windows Updates.
	)
)


:: JOB: Rebuild Windows Update base (deflates the SxS store; note that any Windows Updates installed prior to this point will become uninstallable)
:: Windows 8/2012 and up only
call :log Launch job 'DISM base reset'...
if /i %DRY_RUN%==no (
	if /i not "%WIN_VER:~0,9%"=="Microsoft" (
		if /i not "%WIN_VER:~0,11%"=="Windows V" (
			Dism /online /Cleanup-Image /StartComponentCleanup /ResetBase /Logpath:"%LOGPATH%\tron_dism_base_reset.log" >nul 2>&1
			type "%LOGPATH%\tron_dism_base_reset.log" >> "%LOGPATH%\%LOGFILE%"
			del /f /q "%LOGPATH%\tron_dism_base_reset.log"
			)
		)
	)
call :log Done.

call :log_heading stage_4_patch jobs complete.



:::::::::::::::::::::::
:: STAGE 5: Optimize ::
:::::::::::::::::::::::
:stage_5_optimize
:: Stamp current stage so we can resume if we get interrupted by a reboot
echo stage_5_optimize>tron_stage.txt
title TRON v%SCRIPT_VERSION% [stage_5_optimize]
call :log_heading stage_5_optimize jobs begin...

:: JOB: chkdsk the system drive
call :log Launch job 'chkdsk'...
call :log Checking %SystemDrive% for errors...

:: Run a read-only scan and look for errors. Schedule a scan at next reboot if errors found
if /i %DRY_RUN%==no %SystemRoot%\System32\chkdsk.exe %SystemDrive%
if /i not %ERRORLEVEL%==0 ( 
	call :log_alert Errors found on %SystemDrive%. Scheduling full chkdsk at next reboot.
	if /i %DRY_RUN%==no fsutil dirty set %SystemDrive%
) else (
	call :log No errors found on %SystemDrive%. Skipping full chkdsk at next reboot.
	)
	
call :log Done.


:: Check if we are supposed to run a defrag before doing this section
if "%SKIP_DEFRAG%"=="yes" (
	call :log SKIP_DEFRAG ^(-sd^) set. Skipping defrag.
	call :log_heading stage_5_optimize jobs complete.
	goto stage_6_wrap-up
	)

:: Check if a Solid State hard drive was detected before doing this section
if "%SSD_DETECTED%"=="yes" (
	call :log Solid State hard drive detected. Skipping job 'Defrag %SystemDrive%'.
	call :log_heading stage_5_optimize jobs complete.
	goto stage_6_wrap-up
	)

:: JOB: Defrag the system drive
if "%SSD_DETECTED%"=="no" (
	call :log Launch job 'Defrag %SystemDrive%'...
	if /i %DRY_RUN%==no stage_5_optimize\defrag\defraggler.exe %SystemDrive% /MinPercent 5
	call :log Done.
	call :log_heading stage_5_optimize jobs complete.
	)


::::::::::::::::::::::
:: STAGE 6: Wrap-up ::
::::::::::::::::::::::
:stage_6_wrap-up
:: Stamp current stage so we can resume if we get interrupted by a reboot
echo stage_6_wrap-up>tron_stage.txt
call :log_heading stage_6_wrap-up jobs begin...

:: JOB: If selected, import the original power settings, re-activate them, and delete the backup
:: Otherwise, just reset power settings back to their defaults
if "%PRESERVE_POWER_SCHEME%"=="yes" (
	call :log Restoring power settings to previous values...
	REM Check for Windows XP/2k3
	if /i "%WIN_VER:~0,9%"=="Microsoft" (
		if /i %DRY_RUN%==no %WINDIR%\system32\powercfg.exe /import "%POWER_SCHEME%" /file "%LOGPATH%\tron_power_config_backup.pow"
		if /i %DRY_RUN%==no %WINDIR%\system32\powercfg.exe /setactive "%POWER_SCHEME%"
	) else (
	REM If we made it this far we're not on XP or 2k3 and we can run the standard commands
		if /i %DRY_RUN%==no %WINDIR%\system32\powercfg.exe /import "%LOGPATH%\tron_power_config_backup.pow" %POWER_SCHEME% 2>NUL
		if /i %DRY_RUN%==no %WINDIR%\system32\powercfg.exe /setactive %POWER_SCHEME%
	)
	del %LOGPATH%\tron_power_config_backup.pow 2>NUL
) else (
	call :log Resetting Windows power settings to defaults...
	REM Check for Windows XP/2k3
	if /i "%WIN_VER:~0,9%"=="Microsoft" (
		if /i %DRY_RUN%==no %WINDIR%\system32\powercfg.exe /RestoreDefaultPolicies >NUL 2>&1
	) else (
	REM if we made it this far we're not on XP or 2k3 and we can run the standard commands
		if /i %DRY_RUN%==no %WINDIR%\system32\powercfg.exe -restoredefaultschemes
	)
	call :log Done.
)


:: JOB: If selected, get post-Tron system state (installed programs, complete file list) and generate the summary logs
if /i %GENERATE_SUMMARY_LOGS%==yes (
call :log Summary logs requested, calculating post-run results...
	if /i %DRY_RUN%==no (
		:: Get list of installed programs
		stage_0_prep\log_tools\siv\siv32x.exe -save=[software]="%LOGPATH%\tron_raw_logs\installed-programs-after.txt"
		:: Get list of all files
		stage_0_prep\log_tools\everything\everything.exe -create-filelist %LOGPATH%\tron_raw_logs\filelist-after.txt %SystemDrive%
		:: Parse everything
			REM Step 1: Find FILES that were deleted (second line is to strip everything trailing the first comma from the output)
			stage_0_prep\log_tools\comm\comm.exe -23 %LOGPATH%\tron_raw_logs\filelist-before.txt %LOGPATH%\tron_raw_logs\filelist-after.txt | find /i /v "$RECYCLE" | find /i /v "AppData\" | find /i /v "ntuser.dat" > %TEMP%\temp.txt
			for /f "tokens=1 delims=," %%a in (%TEMP%\temp.txt) do echo %%a >> %LOGPATH%\tron_summary_logs\tron_removed_files.txt
			
			REM Step 2: Find PROGRAMS that were removed. This is super ugly and complicated, but lets us avoid bundling another external utility
			REM Compact the files by removing blank lines, stripping top 4 lines off file, then last two lines, then output to the final text file for comparison
			copy /y %LOGPATH%\tron_raw_logs\installed-programs-before.txt %LOGPATH%\tron_raw_logs\before.txt >NUL
			for /f "delims=" %%a in (%LOGPATH%\tron_raw_logs\before.txt) do echo %%a>> %LOGPATH%\tron_raw_logs\before1.txt
			more +3 %LOGPATH%\tron_raw_logs\before1.txt >> %LOGPATH%\tron_raw_logs\before2.txt
			findstr /v /i "[==" %LOGPATH%\tron_raw_logs\before2.txt > %LOGPATH%\tron_raw_logs\installed-programs-before.txt

			REM AFTER: Compact the files by removing blank lines, stripping top 4 lines off file, then last two lines, then output to the final text file for comparison
			copy /y %LOGPATH%\tron_raw_logs\installed-programs-after.txt %LOGPATH%\tron_raw_logs\after.txt >NUL
			for /f "delims=" %%a in (%LOGPATH%\tron_raw_logs\after.txt) do echo %%a>> %LOGPATH%\tron_raw_logs\after1.txt
			more +3 %LOGPATH%\tron_raw_logs\after1.txt >> %LOGPATH%\tron_raw_logs\after2.txt
			findstr /v /i "[==" %LOGPATH%\tron_raw_logs\after2.txt > %LOGPATH%\tron_raw_logs\installed-programs-after.txt
			
			REM Calculate the differences, using GnuWin32 coreutil's comm.exe
			stage_0_prep\log_tools\comm\comm.exe -23 %LOGPATH%\tron_raw_logs\installed-programs-before.txt %LOGPATH%\tron_raw_logs\installed-programs-after.txt > %LOGPATH%\tron_summary_logs\tron_removed_programs.txt
			
			REM Cleanup
			del /f /q %TEMP%\temp.txt 2>NUL
			del /f /q %LOGPATH%\tron_raw_logs\before*txt 2>NUL
			del /f /q %LOGPATH%\tron_raw_logs\after*txt 2>NUL
	)
call :log Done. Summary logs are at "%LOGPATH%\tron_summary_logs\"
)


:: JOB: Collect misc logs and deposit them in the log folder. Thanks to /u/swtester
call :log Saving misc logs to "%LOGPATH%\tron_raw_logs\"
if exist "%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs" copy /Y "%ProgramData%\Sophos\Sophos Virus Removal Tool\Logs\*.l*" "%LOGPATH%\tron_raw_logs" >NUL
if exist "%ProgramData%\Malwarebytes\Malwarebytes Anti-Malware\Logs" copy /Y "%ProgramData%\Malwarebytes\Malwarebytes Anti-Malware\Logs\*.xml" "%LOGPATH%\tron_raw_logs" >NUL
if exist "%LOGPATH%\mbam-log*" move /y "%LOGPATH%\mbam-log*" "%LOGPATH%\tron_raw_logs\"
if exist "%LOGPATH%\Sophos*" move /y "%LOGPATH%\Sophos*" "%LOGPATH%\tron_raw_logs\"
if exist "%LOGPATH%\protection-log*" move /y "%LOGPATH%\protection-log*" "%LOGPATH%\tron_raw_logs\"
if exist "%LOGPATH%\jre*" move /y "%LOGPATH%\jre*" "%LOGPATH%\tron_raw_logs\"
call :log Done.


:: JOB: Remove resume-related files and registry entries
call :log No crash or reboot detected. Removing resume-support files...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /f /v "tron_resume" >nul 2>&1
del /f /q tron_flags.txt >nul 2>&1
del /f /q tron_stage.txt >nul 2>&1
call :log Done.


:: JOB: Calculate saved disk space
for /F "tokens=2 delims=:" %%a in ('fsutil volume diskfree %SystemDrive% ^| find /i "avail free"') do set bytes=%%a
:: GB version
::set /A FREE_SPACE_BEFORE=%bytes:~0,-3%/1024*1000/1024/1024
:: MB version
set /A FREE_SPACE_AFTER=%bytes:~0,-3%/1024*1000/1024
set /a FREE_SPACE_SAVED=%FREE_SPACE_AFTER% - %FREE_SPACE_BEFORE%


:: Notify of Tron completion
title TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%) [DONE]
call :log_heading DONE. Use \resources\stage_7_manual_tools if further cleaning is required.


:: Check if auto-reboot was requested
if "%AUTO_REBOOT_DELAY%"=="0" (
	call :log_heading_alert Auto-reboot disabled. Recommend rebooting as soon as possible.
) else (
	call :log_heading_alert Auto-reboot selected. Rebooting in %AUTO_REBOOT_DELAY% seconds.
	)


:: Check if shutdown was requested
if /i %AUTO_SHUTDOWN%==yes (
	call :log_heading_alert Auto-shutdown selected. Shutting down in %AUTO_REBOOT_DELAY% seconds.
)


:: Pretend to send the email report. We don't actually send the report here since we need the log trailer which is created below,
:: so we just pretend to send it then actually send it after the log trailer has been created
if /i %EMAIL_REPORT%==yes (
	call :log_heading Email report requested. Sending report now...
	ping localhost -n 5 >NUL
	call :log_heading Done.
)


:: Check if self-destruct was set
if /i %SELF_DESTRUCT%==yes (
	call :log_heading_alert Self-destruct selected. De-rezzing self. Goodbye...
)


:: Display and log the job summary
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------
call :log_heading TRON v%SCRIPT_VERSION% (%SCRIPT_DATE%) complete
echo                          Executed as "%USERDOMAIN%\%USERNAME%" on %COMPUTERNAME%>> %LOGPATH%\%LOGFILE%
echo                          Executed as "%USERDOMAIN%\%USERNAME%" on %COMPUTERNAME%
echo                          Command-line flags: %*>> %LOGPATH%\%LOGFILE%
echo                          Command-line flags: %*
echo                          Safe Mode: %SAFE_MODE% %SAFEBOOT_OPTION%>> %LOGPATH%\%LOGFILE%
echo                          Safe Mode: %SAFE_MODE% %SAFEBOOT_OPTION%
echo                          Free space before Tron run: %FREE_SPACE_BEFORE% MB>> %LOGPATH%\%LOGFILE%
echo                          Free space before Tron run: %FREE_SPACE_BEFORE% MB
echo                          Free space after Tron run:  %FREE_SPACE_AFTER% MB>> %LOGPATH%\%LOGFILE%
echo                          Free space after Tron run:  %FREE_SPACE_AFTER% MB
echo                          Disk space reclaimed:       %FREE_SPACE_SAVED% MB *>> %LOGPATH%\%LOGFILE%
echo                          Disk space reclaimed:       %FREE_SPACE_SAVED% MB *
echo                          Logfile: %LOGPATH%\%LOGFILE%>> %LOGPATH%\%LOGFILE%
echo                          Logfile: %LOGPATH%\%LOGFILE%
echo.
echo   * If you see negative disk space don't panic. Due to how some of Tron's
echo     functions work, actual disk space reclaimed will not be visible until after
echo     a reboot.
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------


:: JOB: Actually send the email report if it was requested
:: This line needed for param5 (/p5) argument sent to SwithMail. It populates a list of command-line flags that were used
set ARGUMENTS='%*'
SETLOCAL ENABLEDELAYEDEXPANSION
if /i %EMAIL_REPORT%==yes (
	if /i %DRY_RUN%==no (
		:: Run this if summary logs weren't requested
		if /i %GENERATE_SUMMARY_LOGS%==no stage_6_wrap-up\email_report\SwithMail.exe /s /x "stage_6_wrap-up\email_report\SwithMailSettings.xml" /a %LOGPATH%\%LOGFILE% /p1 "Tron v%SCRIPT_VERSION% (%SCRIPT_DATE%) executed as %USERDOMAIN%\%USERNAME%" /p2 "%LOGPATH%\%LOGFILE%" /p3 "%SAFE_MODE% %SAFEBOOT_OPTION%" /p4 "%FREE_SPACE_BEFORE%/%FREE_SPACE_AFTER%/%FREE_SPACE_SAVED%" /p5 "%ARGUMENTS%"
	
		:: Run this if summary logs were requested
		if /i %GENERATE_SUMMARY_LOGS%==yes stage_6_wrap-up\email_report\SwithMail.exe /s /x "stage_6_wrap-up\email_report\SwithMailSettings.xml" /a "%LOGPATH%\%LOGFILE%|%LOGPATH%\tron_summary_logs\tron_removed_files.txt|%LOGPATH%\tron_summary_logs\tron_removed_programs.txt" /p1 "Tron v%SCRIPT_VERSION% (%SCRIPT_DATE%) executed as %USERDOMAIN%\%USERNAME%" /p2 "%LOGPATH%\%LOGFILE%" /p3 "%SAFE_MODE% %SAFEBOOT_OPTION%" /p4 "%FREE_SPACE_BEFORE%/%FREE_SPACE_AFTER%/%FREE_SPACE_SAVED%" /p5 "%ARGUMENTS%"

		if %ERRORLEVEL%==0 (
			call :log_heading Done.
		) else (
			call :log_heading_alert Something went wrong, email may not have gone out. Check your settings.
		)
	)
)
ENDLOCAL DISABLEDELAYEDEXPANSION


:: Skip this last bit if we're doing a dry run
if /i %DRY_RUN%==yes goto end_and_skip_shutdown

:: Perform reboot if requested
if /i not "%AUTO_REBOOT_DELAY%"=="0" shutdown -r -f -t %AUTO_REBOOT_DELAY% -c "Rebooting in %AUTO_REBOOT_DELAY% seconds to finish cleanup."

:: Perform shutdown if requested
if /i %AUTO_SHUTDOWN%==yes shutdown -f -t %AUTO_REBOOT_DELAY% -s

:: De-rez self if requested
:self_destruct
set CWD=%CD%
if /i %SELF_DESTRUCT%==yes (
	%SystemDrive%
	cd \
	rmdir /s /q "%CWD%"
	exit
	)

:end_and_skip_shutdown
pause
ENDLOCAL
exit /B
:: That's all, folks




:::::::::::::::::::::::
:: LOGGING FUNCTIONS ::
:::::::::::::::::::::::
:: These are the functions for logging. Thanks to /u/douglas_swehla for helping me learn about faking functions in batch
:log_heading
echo %CUR_DATE% %TIME%   %*>> "%LOGPATH%\%LOGFILE%"  
echo %CUR_DATE% %TIME%   %*
goto :eof

:log_heading_alert
echo %CUR_DATE% %TIME% ! %*>> "%LOGPATH%\%LOGFILE%"  
echo %CUR_DATE% %TIME% ! %*
goto :eof

:log
echo %CUR_DATE% %TIME%    %*>> "%LOGPATH%\%LOGFILE%"  
echo %CUR_DATE% %TIME%    %*
goto :eof

:log_alert
echo %CUR_DATE% %TIME% !  %*>> "%LOGPATH%\%LOGFILE%"  
echo %CUR_DATE% %TIME% !  %*
goto :eof

:eof
