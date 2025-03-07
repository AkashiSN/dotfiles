@echo off
SETLOCAL EnableDelayedExpansion
goto :main

:main
SETLOCAL

rem Configuration
SET AWS_REGION=ap-northeast-1
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
	--query InstanceInformationList[0].PingStatus ^
	--profile %AWS_PROFILE% ^
	--region %AWS_REGION% > %USERPROFILE%\.ssh\%HOST%_status.temp
@echo off
SET /p STATUS=<%USERPROFILE%\.ssh\%HOST%_status.temp

rem If the instance is online, start the session
IF "%STATUS%" == "Online" (
	aws ec2-instance-connect open-tunnel ^
	--instance-id=%HOST% ^
	--profile %AWS_PROFILE%
) ELSE (
	aws ec2 start-instances --instance-ids %HOST% --profile %AWS_PROFILE% --region %AWS_REGION%
	ping -n %SLEEP_DURATION% 127.0.0.1 >NUL

	SET /a COUNT=1

	:loop
	if !COUNT! LEQ !MAX_ITERATION! (
		@echo on
		aws ssm describe-instance-information ^
			--filters Key=InstanceIds,Values=%HOST% ^
			--output text ^
			--query InstanceInformationList[0].PingStatus ^
			--profile %AWS_PROFILE% ^
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
	echo.
	echo Outside of loop^^!

	:start_session
	rem Instance is online now - start the session
	aws ec2-instance-connect open-tunnel ^
	--instance-id %HOST% ^
	--profile %AWS_PROFILE%
)

ENDLOCAL

EXIT /b 0

rem ssh-config

rem Host HOSTNAME_ALIAS
rem   HostName i-asdfgxcvb98ubcxbv
rem   User ec2-user
rem   ForwardAgent yes
rem
rem Match host i-*
rem   ProxyCommand C:\Users\S048541\.ssh\eice-proxy.bat %h %p %r {aws_profile}

rem  !!! %USERPROFILE% not working
