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

@echo on
aws ssm describe-instance-information ^
	--filters Key=InstanceIds,Values=%HOST% ^
	--output text ^
	--query InstanceInformationList[0].PingStatus > %USERPROFILE%\.ssh\%HOST%_status.temp
@echo off
SET /p STATUS=<%USERPROFILE%\.ssh\%HOST%_status.temp

rem If the instance is online, start the session
IF "%STATUS%" == "Online" (
	aws ssm start-session --target %HOST% ^
	--document-name AWS-StartSSHSession ^
	--parameters portNumber=%PORT%
) ELSE (
	aws ec2 start-instances --instance-ids %HOST%
	ping -n %SLEEP_DURATION% 127.0.0.1 >NUL

	SET /a COUNT=1

	:loop
	if !COUNT! LEQ !MAX_ITERATION! (
		@echo on
		aws ssm describe-instance-information ^
			--filters Key=InstanceIds,Values=%HOST% ^
			--output text ^
			--query InstanceInformationList[0].PingStatus ^
			--region %AWS_REGION% > %USERPROFILE%\.ssh\%HOST%_status.temp
		@echo off
		SET /p STATUS=<%USERPROFILE%\.ssh\%HOST%_status.temp

		IF "%STATUS%" == "Online" (
			GOTO :start_session
		)
		echo RETRY !COUNT!
		set /a COUNT=!COUNT!+1
		ping -n %SLEEP_DURATION% 127.0.0.1 >NUL

		GOTO :loop
	)

	EXIT /b 1

	:start_session
	rem Instance is online now - start the session
	aws ssm start-session --target %HOST% ^
	--document-name AWS-StartSSHSession ^
	--parameters portNumber=%PORT%
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
rem   ProxyCommand C:\Users\{user}\.ssh\ssm-proxy.bat %h %p %r {aws_profile}

rem  !!! %USERPROFILE% not working
