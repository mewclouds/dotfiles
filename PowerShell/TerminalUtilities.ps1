function CommandExists {
    Param ($command)
    $preference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { if (Get-Command $command) { RETURN $true } }
    Catch { Write-Host "$command does not exist"; RETURN $false }
    Finally { $ErrorActionPreference = $preference }
}


# Unix-like sudo
function sudo { 
    Start-Process wt -Verb runAs
}

# Open the current directory in the file explorer
function here() { Invoke-Item . }

# Unix-like which command
function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }

# Unix-like touch command
function touch() { New-Item -ItemType File -Name $args[0] }

# Replace the current directory with the home directory
function pwdd { $("$PWD".replace($HOME, '~')) }

# Clear the console and history
function rmh() { Remove-Item (Get-PSReadlineOption).HistorySavePath }

# Compute file hashes
function sha1 { Get-FileHash -Algorithm SHA1 $args }
function sha256 { Get-FileHash -Algorithm SHA256 $args }

#region git

### Git Aliases/Utilities
function ginit() {
    git init
    git add .
    git commit -m "feat: initialize repository"
}

function glog() {
    git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative
}

function gd() { git diff --color }

function lazycom() {
    git add .
    git commit -m "$args"
    gpsh
}

function gst() { git status -sb }

function gpsh() { git push origin HEAD }

function gpl() { git pull --prune }

function gco() {
    git checkout $args
    Write-Host "Switched to branch: " -NoNewline; Write-Host $args -ForegroundColor Cyan
}
#endregion