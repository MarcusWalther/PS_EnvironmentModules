$script:moduleCacheFileLocation = [IO.Path]::Combine($script:tmpEnvironmentRootPath, "ModuleCache.xml")
$script:searchPathsFileLocation = [IO.Path]::Combine($script:configEnvironmentRootPath, "CustomSearchPaths.xml")

function Initialize-EnvironmentModuleCache()
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

function Initialize-CustomSearchPaths()
{
    <#
    .SYNOPSIS
    Load the custom search paths file.
    .DESCRIPTION
    This function will load all environment modules that part of the cache file and will provide them in the environemtModules list.
    .OUTPUTS
    No output is returned.
    #>
    $script:customSearchPaths = New-Object "System.Collections.Generic.Dictionary[String, System.Collections.Generic.List[EnvironmentModules.SearchPath]]"

    $fileInfo = New-Object "System.IO.FileInfo" -ArgumentList $script:searchPathsFileLocation
    if(($null -eq $fileInfo) -or ($fileInfo.Length -eq 0)) {
        return
    }

    $knownTypes = New-Object "System.Collections.Generic.List[System.Type]"
    $knownTypes.Add([EnvironmentModules.SearchPath])

    $serializer = New-Object "System.Runtime.Serialization.DataContractSerializer" -ArgumentList $script:customSearchPaths.GetType(), $knownTypes

    $fileStream = $null
    try {
        $fileStream = New-Object "System.IO.FileStream" -ArgumentList $script:searchPathsFileLocation, ([System.IO.FileMode]::Open)
        $reader = $null
        try {
            $reader = [System.Xml.XmlDictionaryReader]::CreateTextReader($fileStream, (New-Object "System.Xml.XmlDictionaryReaderQuotas"))
            $script:customSearchPaths = $serializer.ReadObject($reader)
        }
        finally {
            if ($null -ne $reader)
            {            
                $reader.Close()
            }
        }        
    }
    finally {
        if ($null -ne $fileStream)
        {
            $fileStream.Dispose()
        }
    }
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
    Remove-Item $script:tmpEnvironmentModulePath\* -Force -Recurse    
    
    foreach ($module in (Get-Module -ListAvailable)) {
        Write-Verbose "Module $($module.Name) depends on $($module.RequiredModules)"
        $isEnvironmentModule = ("$($module.RequiredModules)" -match "EnvironmentModules")
        if($isEnvironmentModule) {
            Write-Verbose "Environment module $($module.Name) found"
            $script:environmentModules = $script:environmentModules + (New-EnvironmentModuleInfoBase -ModuleFullName $module.Name)
            $moduleNameParts = Split-EnvironmentModuleName $module.Name
            
            if($null -eq $moduleNameParts[1]) {
              $moduleNameParts[1] = ""
            }
            
            if($null -eq $moduleNameParts[2]) {
              $moduleNameParts[2] = ""
            }
            
            # Read the environment module properties from the pse1 file
            $info = New-EnvironmentModuleInfoBase -Module $module

            if($info.ModuleType -ne [EnvironmentModules.EnvironmentModuleType]::Default) {
                continue; #Ignore meta and abstract modules
            }

            # Add the module to the list of all modules
            $allModuleNames.Add($module.Name) > $null
            
            # Handle the module by architecture (if architecture is specified)
            if($moduleNameParts[2] -ne "") {
                $dictionaryKey = [System.Tuple]::Create($moduleNameParts[0],$moduleNameParts[2])
                $dictionaryValue = [System.Tuple]::Create($moduleNameParts[1], $module)
                $oldItem = $modulesByArchitecture.Get_Item($dictionaryKey)
                
                if($null -eq $oldItem) {
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
            
            if($null -eq $oldItem) {
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
      
      Write-Verbose "Creating module with name $moduleName"

      #Check if there is no module with the default name
      if($allModuleNames.Contains($moduleName)) {
        Write-Verbose "The module $moduleName is not generated, because it does already exist"
        continue
      }
      
      
      [EnvironmentModules.ModuleCreator]::CreateMetaEnvironmentModule($moduleName, $script:tmpEnvironmentModulePath, ([IO.Path]::Combine($moduleFileLocation, "..\")), $true, "", $null)
      Write-Verbose "EnvironmentModule $moduleName generated"
      $script:environmentModules = $script:environmentModules + (New-Object EnvironmentModules.EnvironmentModuleInfoBase -ArgumentList @($moduleName, [EnvironmentModules.EnvironmentModuleType]::Meta))
    }
    
    foreach($module in $modulesByVersion.GetEnumerator()) {
      $moduleName = $module.Key
      
      Write-Verbose "Creating module with name $moduleName"

      #Check if there is no module with the default name
      if($allModuleNames.Contains($moduleName)) {
        Write-Verbose "The module $moduleName is not generated, because it does already exist"
        continue
      }
      
      
      [EnvironmentModules.ModuleCreator]::CreateMetaEnvironmentModule($moduleName, $script:tmpEnvironmentModulePath, ([IO.Path]::Combine($moduleFileLocation, "..\")), $true, "", $null)
      Write-Verbose "EnvironmentModule $moduleName generated"
      $script:environmentModules = $script:environmentModules + (New-Object EnvironmentModules.EnvironmentModuleInfoBase -ArgumentList @($moduleName, [EnvironmentModules.EnvironmentModuleType]::Meta))
    }    
    
    Write-Verbose "By Architecture"
    Write-Verbose $modulesByArchitecture.GetEnumerator()
    Write-Verbose "By Version"
    Write-Verbose $modulesByVersion.GetEnumerator()

    Export-Clixml -Path "$moduleCacheFileLocation" -InputObject $script:environmentModules
}

function Add-EnvironmentModuleSearchPath
{
    <#
    .SYNOPSIS
    Add a new custom search path for an environment module.
    .DESCRIPTION
    This function will register a new custom search path for a module.
    .PARAMETER Type
    The type of the search path.
    .PARAMETER Key
    The key to set - the key of the class EnvironmentModules.SearchPath.
    .PARAMETER Module
    The module that should be extended with a new search path.
    .PARAMETER SubFolder
    The sub folder for the search.
    .OUTPUTS
    List of all search paths.
    #>
    [cmdletbinding()]
    Param()
    DynamicParam {
        $runtimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        $moduleSet = $script:environmentModules | Select-Object -ExpandProperty FullName
        Add-DynamicParameter 'ModuleFullName' String $runtimeParameterDictionary -Mandatory $True -Position 0 -ValidateSet $moduleSet

        Add-DynamicParameter 'Type' String $runtimeParameterDictionary -Mandatory $True -Position 1 -ValidateSet @("Directory", "Registry", "Environment")
        Add-DynamicParameter 'Key' String $runtimeParameterDictionary -Mandatory $True -Position 2
        Add-DynamicParameter 'SubFolder' String $runtimeParameterDictionary -Mandatory $False -Position 3

        return $runtimeParameterDictionary
    }

    begin {
        $ModuleFullName = $PsBoundParameters['ModuleFullName']
        $Type = $PsBoundParameters['Type']
        $Key = $PsBoundParameters['Key']
        $SubFolder = $PsBoundParameters['SubFolder']

        if(-not $SubFolder) {
            $SubFolder = ""
        }
    }

    process {   
        $oldSearchPaths = $script:customSearchPaths[$ModuleFullName]
        $newSearchPath
        if($Type -eq "Directory") {
            $newSearchPath = New-Object EnvironmentModules.DirectorySearchPath -ArgumentList @($Key, $SubFolder, 40, $false)
        }
        else {
            if($Type -eq "Registry") {
                $newSearchPath = New-Object EnvironmentModules.RegistrySearchPath -ArgumentList @($Key, $SubFolder, 40, $false)
            }
            else {
                $newSearchPath = New-Object EnvironmentModules.EnvironmentSearchPath -ArgumentList @($Key, $SubFolder, 40, $false)
            }
        }

        if($oldSearchPaths) {
            $oldSearchPaths.Add($newSearchPath)
            $script:customSearchPaths[$ModuleFullName] = $oldSearchPaths
        }
        else {
            $searchPaths = New-Object "System.Collections.Generic.List[EnvironmentModules.SearchPath]"
            $searchPaths.Add($newSearchPath)
            $script:customSearchPaths[$ModuleFullName] = $searchPaths
        }

        Write-CustomSearchPaths
    }
}

function Remove-EnvironmentModuleSearchPath
{
    <#
    .SYNOPSIS
    Remove a previously defined custom search path from the given module.
    .DESCRIPTION
    This function will remove a new custom search path from the module. If multiple search paths are found, an additional select dialogue is displayed.
    .PARAMETER ModuleFullName
    The module that should be checked.    
    .PARAMETER Type
    The type of the search path to remove.
    .PARAMETER Key
    The key of the search path to remove.
    .PARAMETER SubFolder
    The sub folder of the search path to remove.
    .OUTPUTS
    List of all search paths.
    #>    
    [CmdletBinding()]
    Param()
    DynamicParam {
        $runtimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        $moduleSet = $script:environmentModules | Select-Object -ExpandProperty FullName
        Add-DynamicParameter 'ModuleFullName' String $runtimeParameterDictionary -Mandatory $True -Position 0 -ValidateSet $moduleSet

        Add-DynamicParameter 'Type' String $runtimeParameterDictionary -Mandatory $False -Position 1 -ValidateSet @("*", "Directory", "Registry", "Environment")
        Add-DynamicParameter 'Key' String $runtimeParameterDictionary -Mandatory $False -Position 2
        Add-DynamicParameter 'SubFolder' String $runtimeParameterDictionary -Mandatory $False -Position 3

        return $runtimeParameterDictionary
    }

    begin {
        $ModuleFullName = $PsBoundParameters['ModuleFullName']
        $Type = $PsBoundParameters['Type']
        $Key = $PsBoundParameters['Key']
        $SubFolder = $PsBoundParameters['SubFolder']

        if(-not $Type) {
            $Type = "*"
        }
        if(-not $Key) {
            $Key = "*"
        }        
        if(-not $SubFolder) {
            $SubFolder = ""
        } 
    }

    process {
        $customSearchPaths = Get-EnvironmentModuleSearchPath -ModuleName $ModuleFullName -Type $Type -Key $Key -SubFolder $SubFolder -Custom
        if($null -eq $customSearchPaths) {
            return
        }

        $oldSearchPaths = $script:customSearchPaths[$ModuleFullName]
        if($customSearchPaths -is [array]) {
            $searchPaths = @{}
            $searchPathOptions = @()
            foreach($customSearchPath in $customSearchPaths) {
                $searchPathKey = $customSearchPath.ToString()
                $searchPaths[$searchPathKey] = $customSearchPath
                $searchPathOptions = $searchPathOptions + $searchPathKey
            }

            $customSearchPath = Show-SelectDialogue $searchPathOptions "Select the custom search path to remove"
            $customSearchPath = $searchPaths[$customSearchPath]
        }
        else {
            $customSearchPath = $customSearchPaths    # Just one search path matches the filter
        }

        if(-not $customSearchPath) {
            return
        }

        $_ = $oldSearchPaths.Remove($customSearchPath)
        $script:customSearchPaths[$ModuleFullName] = $oldSearchPaths
        Write-CustomSearchPaths
    }
}

function Get-EnvironmentModuleSearchPath
{
    <#
    .SYNOPSIS
    Get the search paths defined for the module(s).
    .DESCRIPTION
    This function will list all search paths for environment modules matching the given name filter.
    .PARAMETER ModuleName
    The module name filter to consider.
    .PARAMETER Type
    The search path type to use as filter.    
    .PARAMETER Key
    The key value to use as filter.
    .PARAMETER SubFolder
    The sub folder to use as filter.    
    .PARAMETER Custom
    True if only custom search paths should be returned.        
    .OUTPUTS
    List of all search paths.
    #>
    Param(
        [String] $ModuleName = "*",
        [ValidateSet("*", "Directory", "Registry", "Environment")]
        [string] $Type = "*",
        [Parameter(Mandatory=$false)]
        [string] $Key = "*",
        [Parameter(Mandatory=$false)]
        [string] $SubFolder = "*",
        [switch] $Custom
    )

    $modules = Get-EnvironmentModule -ListAvailable $ModuleName

    foreach($module in $modules) {
        foreach($searchPath in $module.SearchPaths) {
            if($Custom -and $searchPath.IsDefault) {
                continue
            }

            if(-not ($searchPath.Type.ToString() -like $Type)) {
                continue
            }      
            
            if(-not ($searchPath.Key -like $Key)) {
                continue
            }      
            
            if(-not ($searchPath.SubFolder -like $SubFolder)) {
                continue
            }             
            
            $searchPath.ToInfo($module.FullName)
        }
    }
}

function Clear-EnvironmentModuleSearchPaths
{
    <#
    .SYNOPSIS
    Deletes all custom search paths.
    .DESCRIPTION
    This function will delete all custom search paths that are defined by the user.
    .PARAMETER Force
    Do not ask for deletion.   
    .OUTPUTS
    No output is returned.
    #>    
    Param(
        [Switch] $Force
    )

    # Ask for deletion
    if(-not $Force) {
        $answer = Read-Host -Prompt "Do you really want to delete all custom seach paths (Y/N)?"

        if($answer.ToLower() -ne "y") {
            return
        }
    }

    $script:customSearchPaths.Clear()
    Write-CustomSearchPaths
}

function Write-CustomSearchPaths
{
    <#
    .SYNOPSIS
    Write the defined custom search paths to the configuration file.
    .DESCRIPTION
    This function will write all added custom search paths to the configuration file.
    .OUTPUTS
    No output is returned.
    #>      
    $knownTypes = New-Object "System.Collections.Generic.List[System.Type]"
    $knownTypes.Add([EnvironmentModules.SearchPath])

    $serializer = New-Object "System.Runtime.Serialization.DataContractSerializer" -ArgumentList $script:customSearchPaths.GetType(), $knownTypes
    $fileStream = $null
    try {
        $fileStream = New-Object "System.IO.FileStream" -ArgumentList $script:searchPathsFileLocation, ([System.IO.FileMode]::Create)
        $writer = $null
        try {
            $writer = New-Object "System.IO.StreamWriter" -ArgumentList $fileStream, ([System.Text.Encoding]::UTF8)
            $xmlWriter = $null
            try {
                $xmlWriter = [System.Xml.XmlTextWriter]($writer)
                $xmlWriter.Formatting = [System.Xml.Formatting]::Indented
                $xmlWriter.WriteStartDocument()
                $serializer.WriteObject($xmlWriter, $script:customSearchPaths)
                $xmlWriter.Flush()
            }
            finally {
                if($null -ne $xmlWriter) {
                    $xmlWriter.Close()
                }
            }
        }
        finally {
            if($null -ne $writer) {
                $writer.Close()
            }
        }
    }
    finally {
        if($null -ne $fileStream) {
            $fileStream.Close()
        }
    }
}