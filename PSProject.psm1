$script:__PROJECT = $null
$script:__PROMPT = ${function:prompt}

function New-PSProject {
    param(
        [Parameter(Mandatory)]
        [string]
        $Name,
        [Parameter()]
        [string]
        $Path=(Join-Path (Get-Location) $Name)
    )
    process {      
        Write-Host "Creating module '$Name' in '$Path'"

        New-Item -Path $Path -ItemType Directory
        Push-Location -Path $Path 
        try {            
            New-Item -Path 'src' -ItemType Directory
            New-Item -Path "src/$Name.psm1" -ItemType File
            New-Item -Path 'src/private' -ItemType Directory
            New-Item -Path 'src/public' -ItemType Directory

            New-Item -Path 'build' -ItemType Directory

            New-Item '.psproj' -ItemType File


@"
`$p = Get-ChildItem "`$PSScriptRoot/private" '*.ps1'
`$p | ForEach-Object {
    . `$_
}
`$p = Get-ChildItem "`$PSScriptRoot/public" '*.ps1'
`$p | ForEach-Object {
    . `$_
}
Export-ModuleMember -Function `$p.BaseName
"@ | Out-File "src/$Name.psm1"


        } finally {
            Pop-Location
        }
    }
}

function Enter-PSProject {
    param(
        [Parameter(Mandatory, ParameterSetName='Name')]
        [string]
        $Name,
        [Parameter(Mandatory, ParameterSetName='Path')]
        [string]
        $Path
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Name') {
            $Path = Join-Path (Get-Location) $Name
        } else {
            $Name = ([System.IO.FileInfo]$Path).BaseName
        }

        if (Test-Path "$Path/.psproj") {
            if ($null -ne $script:__PROJECT) {
                Exit-PSProject
            }

            $ap = @{
                Name=$Name;
                Path=$Path;
                Watcher=[System.IO.FileSystemWatcher]::new();
                WatcherEventHandler=$null;
                LastEventId=-1;
                ModulePath="$Path/src/$Name.psm1";
                PS1Backup=$function:prompt;
                Verbose=[bool]$PSBoundParameters.Verbose;                
            }     

            $ap.Watcher.Path = "$Path/src"
            $ap.Watcher.Filter = '*.ps1'
            $ap.Watcher.IncludeSubdirectories = $true
            $ap.Watcher.EnableRaisingEvents = $true
            
            $eh = [ScriptBlock]{
                $ap = $Event.MessageData
                if ($ap.LastEventId -ne $Event.EventIdentifier - 1) {                    
                    $ap.LastEventId = $Event.EventIdentifier    
                    Import-Module $ap.ModulePath -Force -Global -Verbose:$ap.Verbose
                }
            }
            
            $ap.WatcherEventHandlers = @(
                (Register-ObjectEvent $ap.Watcher -EventName Changed -Action $eh -MessageData $ap),
                (Register-ObjectEvent $ap.Watcher -EventName Created -Action $eh -MessageData $ap),
                (Register-ObjectEvent $ap.Watcher -EventName Deleted -Action $eh -MessageData $ap),
                (Register-ObjectEvent $ap.Watcher -EventName Renamed -Action $eh -MessageData $ap)
            )       
            
            $function:prompt = "Write-Host '[PSProject: $Name] ' -ForegroundColor Blue -NoNewline; $script:__PROMPT;"

            $script:__PROJECT = $ap
        } else {
            throw "No project in $Path"
        }
    }
}

function Exit-PSProject {
    [CmdletBinding()]
    param()
    process {
        $ap = $script:__PROJECT
        if ($null -ne $ap.Watcher) {
            $ap.Watcher.Dispose()
            $ap.WatcherEventHandlers | ForEach-Object {
                $_.Dispose()
            }
            $ap.Watcher = $null
        }        
        
        $function:prompt = $script:__PROMPT

        $script:__PROJECT = $null
    }  
}

function Build-PSProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName='Name')]
        [string]
        $Name,
        [Parameter(Mandatory, ParameterSetName='Path')]
        [string]
        $Path
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Name') {
            $Path = Join-Path (Get-Location) $Name
        } else {
            $Name = ([System.IO.FileInfo]$Path).BaseName
        }

        Remove-Item "$Path/build" -Force -Recurse -ErrorAction Ignore
        New-Item "$Path/build" -Force -ItemType Directory

        Push-Location "$Path/build"
        try {            
            $p = Get-ChildItem "$Path/src/private"
            $p | Get-Content | Out-File "$Name.psm1" -Append
            $p = Get-ChildItem "$Path/src/public"
            $p | Get-Content | Out-File "$Name.psm1" -Append
            "Export-ModuleMember '$($p.BaseName -join "','")'" | Out-File "$Name.psm1" -Append
        } finally {
            Pop-Location
        }     
    }
}

Export-ModuleMember -Function 'New-PSProject'
Export-ModuleMember -Function 'Enter-PSProject'
Export-ModuleMember -Function 'Exit-PSProject'
Export-ModuleMember -Function 'Build-PSProject'