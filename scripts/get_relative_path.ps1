$strip_args = @();

foreach ($arg in $args) {
    if($arg.Contains('Temp')) {
        if($arg.Contains('/')) {
            $strip_args += $($arg -split '/')[-1]
        } elseif ($arg.Contains('\')){
            $strip_args += $($arg -split '\\')[-1]
        }
    } else {
        $strip_args += $arg
    }
}

Write-Host $strip_args
