﻿# Creata a empty collection of known and loaded environment modules first
[HashTable] $loadedEnvironmentModules = @{}

$moduleFileLocation = $MyInvocation.MyCommand.ScriptBlock.Module.Path
$script:tmpEnvironmentRootPath = ([IO.Path]::Combine($moduleFileLocation, "..\Tmp\"))
$tmpEnvironmentModulePath = ([IO.Path]::Combine($script:tmpEnvironmentRootPath, "Modules"))
$moduleCacheFileLocation = [IO.Path]::Combine($script:tmpEnvironmentRootPath, "ModuleCache.xml")

mkdir $script:tmpEnvironmentRootPath -Force
mkdir $tmpEnvironmentModulePath -Force

$env:PSModulePath = "$env:PSModulePath;$tmpEnvironmentModulePath"
$script:environmentModules = @()
$silentUnload = $false

function Load-EnvironmentModuleCache()
{
    <#
    .SYNOPSIS
    Load the environment modules cache file.
    .DESCRIPTION
    This function will load all environment modules that part of the cache file and will provide them in the environemtModules list.
    .OUTPUTS
    No output is returned.
    #>
    $script:environmentModules = @()
    if(-not (test-path $moduleCacheFileLocation))
    {
        return
    }
    
    $script:environmentModules = Import-CliXml -Path $moduleCacheFileLocation
}

function Split-EnvironmentModuleName([String] $Name)
{
    <#
    .SYNOPSIS
    Splits the given name into an array with 4 parts (name, version, architecture, additionalOptions).
    .DESCRIPTION
    Split a name string that either has the format 'Name-Version-Architecture' or just 'Name'. The output is 
    an array with the 4 parts (name, version, architecture, additionalOptions). If a value was not specified, 
    $null is returned at the according array index.
    .PARAMETER Name
    The name-string that should be splitted.
    .OUTPUTS
    A string array with 4 parts (name, version, architecture, additionalOptions) 
    #>
    $doesMatch = $Name -match '^(?<name>[0-9A-Za-z]+)((-(?<version>([0-9]+_[0-9]+)|(DEF|DEV|NIGHTLY)))|(?<version>))((-(?<architecture>(x64|x86)))|(?<architecture>))((-(?<additionalOptions>[0-9A-Za-z]+))|(?<additionalOptions>))$'
    if($doesMatch) 
    {
        if($matches.version -eq "") {
            $matches.version = $null
        }
        if($matches.architecture -eq "") {
            $matches.architecture = $null
        }
        if($matches.additionalOptions -eq "") {
            $matches.additionalOptions = $null
        }
        
        Write-Verbose "Splitted $Name into parts:"
        Write-Verbose ("Name: " + $matches.name)
        Write-Verbose ("Version: " + $matches.version)
        Write-Verbose ("Architecture: " + $matches.architecture)
        Write-Verbose ("Additional Options: " + $matches.additionalOptions)
        
        return $matches.name, $matches.version, $matches.architecture, $matches.additionalOptions
    }
    else
    {
        Write-Host ("The environment module name " + $Name + " is not correctly formated. It must be 'Name-Version-Architecture-AdditionalOptions'") -foregroundcolor "Red"
        return $null
    }
}

function Split-EnvironmentModule([EnvironmentModules.EnvironmentModule] $Module)
{
    <#
    .SYNOPSIS
    Converts the given environment module into an array with 4 parts (name, version, architecture, additionalOptions).
    .DESCRIPTION
    Converts an environment module into an array with 4 parts (name, version, architecture, additionalOptions), to make 
    it comparable to the output of the Split-EnvironmentModuleName function.
    .PARAMETER Module
    The module object that should be transformed.
    .OUTPUTS
    A string array with 4 parts (name, version, architecture, additionalOptions) 
    #>
    return $Module.Name, $Module.Version, $Module.Architecture, $Module.AdditionalOptions
}

function Update-EnvironmentModuleCache()
{
    <#
    .SYNOPSIS
    Search for all modules that depend on the environment module and add them to the cache file.
    .DESCRIPTION
    This function will clear the cache file and later iterate over all modules of the system. If the module depends on the environment module, 
    it is added to the cache file.
    .OUTPUTS
    No output is returned.
    #>
    $script:environmentModules = @()
    $modulesByArchitecture = @{}
    $modulesByVersion = @{}
    $allModuleNames = New-Object 'System.Collections.Generic.HashSet[String]'
    
    # Delete all temporary modules created previously
    Remove-Item $tmpEnvironmentModulePath\* -Force -Recurse    
    
    foreach ($module in (Get-Module -ListAvailable)) {
        Write-Verbose "Module $($module.Name) depends on $($module.RequiredModules)"
        $isEnvironmentModule = ("$($module.RequiredModules)" -match "EnvironmentModules")
        if($isEnvironmentModule) {
            Write-Verbose "Environment module $($module.Name) found"
            $script:environmentModules = $script:environmentModules + $module.Name
            $moduleNameParts = Split-EnvironmentModuleName $module.Name
            
            if($moduleNameParts[1] -eq $null) {
              $moduleNameParts[1] = ""
            }
            
            if($moduleNameParts[2] -eq $null) {
              $moduleNameParts[2] = ""
            }
            
            # Add the module to the list of all modules
            $unused = $allModuleNames.Add($module.Name)
            
            if($moduleNameParts[0] -eq "Project") {
                continue; #Ignore project modules
            }
            
            # Handle the module by architecture (if architecture is specified)
            if($moduleNameParts[2] -ne "") {
                $dictionaryKey = [System.Tuple]::Create($moduleNameParts[0],$moduleNameParts[2])
                $dictionaryValue = [System.Tuple]::Create($moduleNameParts[1], $module)
                $oldItem = $modulesByArchitecture.Get_Item($dictionaryKey)
                
                if($oldItem -eq $null) {
                    $modulesByArchitecture.Add($dictionaryKey, $dictionaryValue)
                }
                else {
                    if(($oldItem.Item1) -lt $moduleNameParts[1]) {
                      $modulesByArchitecture.Set_Item($dictionaryKey, $dictionaryValue)
                    }
                }
            }
            
            # Handle the module by version (if version is specified)
            $dictionaryKey = $moduleNameParts[0]
            $dictionaryValue = [System.Tuple]::Create($moduleNameParts[1], $module)
            $oldItem = $modulesByVersion.Get_Item($dictionaryKey)
            
            if($oldItem -eq $null) {
                $modulesByVersion.Add($dictionaryKey, $dictionaryValue)
                continue
            }
            
            if(($oldItem.Item1) -lt $moduleNameParts[1]) {
              $modulesByVersion.Set_Item($dictionaryKey, $dictionaryValue)
            }
        }
    }
 
    foreach($module in $modulesByArchitecture.GetEnumerator()) {
      $moduleName = "$($module.Key.Item1)-$($module.Key.Item2)"
      $defaultModule = $module.Value.Item2
      
      Write-Verbose "Creating module with name $moduleName"

      #Check if there is no module with the default name
      if($allModuleNames.Contains($moduleName)) {
        Write-Verbose "The module $moduleName is not generated, because it does already exist"
        continue
      }
      
      
      [EnvironmentModules.ModuleCreator]::CreateMetaEnvironmentModule($moduleName, $tmpEnvironmentModulePath, $defaultModule, ([IO.Path]::Combine($moduleFileLocation, "..\")))
      Write-Verbose "EnvironmentModule $moduleName generated"
      $script:environmentModules = $script:environmentModules + $moduleName
    }
    
    foreach($module in $modulesByVersion.GetEnumerator()) {
      $moduleName = $module.Key
      $defaultModule = $module.Value.Item2
      
      Write-Verbose "Creating module with name $moduleName"

      #Check if there is no module with the default name
      if($allModuleNames.Contains($moduleName)) {
        Write-Verbose "The module $moduleName is not generated, because it does already exist"
        continue
      }
      
      
      [EnvironmentModules.ModuleCreator]::CreateMetaEnvironmentModule($moduleName, $tmpEnvironmentModulePath, $defaultModule, ([IO.Path]::Combine($moduleFileLocation, "..\")))
      Write-Verbose "EnvironmentModule $moduleName generated"
      $script:environmentModules = $script:environmentModules + $moduleName
    }    
    
    Write-Host "By Architecture"
    $modulesByArchitecture.GetEnumerator()
    Write-Host "By Version"
    $modulesByVersion.GetEnumerator()

    Export-Clixml -Path "$moduleCacheFileLocation" -InputObject $script:environmentModules
}

# Check if the cache file is available -> create it if not
if(test-path $moduleCacheFileLocation)
{
    Load-EnvironmentModuleCache
}
else
{
    Update-EnvironmentModuleCache
}

# Include all required functions
. "${PSScriptRoot}\Utils.ps1"
. "${PSScriptRoot}\EnvironmentModules.ps1"