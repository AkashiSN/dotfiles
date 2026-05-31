@echo off
SETLOCAL EnableDelayedExpansion
goto :main

:main
SETLOCAL

rem Configuration
SET MAX_ITERATION=20
SET SLEEP_DURATION=5

SET HOST=%~1
SET PORT=%~2
SET USER=%~3
SET AWS_PROFILE=%~4

for /f "usebackq delims=" %%A in (`^
	aws ec2 describe-instances ^
		--instance-ids %HOST% ^
		--query Reservations[0].Instances[0].State.Code ^
`)do (
	set STATUS=%%A
)

rem If the instance is online, start the session
IF "%STATUS%" == "16" (
	aws ec2-instance-connect open-tunnel --instance-id=%HOST%
) ELSE (
	aws ec2 start-instances --instance-ids %HOST%
	ping -n %SLEEP_DURATION% 127.0.0.1 >NUL

	SET /a COUNT=1

	:loop
	if !COUNT! LEQ !MAX_ITERATION! (
		for /f "usebackq delims=" %%A in (`^
			aws ec2 describe-instances ^
				--instance-ids %HOST% ^
				--query Reservations[0].Instances[0].State.Code ^
		`)do (
			set STATUS=%%A
		)

		IF "%STATUS%" == "16" (
			GOTO :start_session
		)
		echo RETRY !COUNT!
		set /a COUNT=!COUNT!+1
		ping -n %SLEEP_DURATION% 127.0.0.1 >NUL

		GOTO :loop
	)

	EXIT /b 1

	:start_session
	ping -n %SLEEP_DURATION% 127.0.0.1 >NUL
	rem Instance is online now - start the session
	aws ec2-instance-connect open-tunnel --instance-id %HOST%
)

ENDLOCAL

EXIT /b 0

rem ssh-config

rem Host HOSTNAME_ALIAS
rem   HostName      i-asdfgxcvb98ubcxbv
rem   User          ec2-user
rem   ForwardAgent  yes
rem   IdentityFile  ~/.ssh/id_ed25519
rem
rem Match host i-*
rem   ProxyCommand C:\Users\{user}\.ssh\eice-proxy.bat %h %p %r {aws_profile}

rem  !!! %USERPROFILE% not working
