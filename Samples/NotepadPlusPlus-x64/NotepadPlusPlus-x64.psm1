param(
    [parameter(Position=0, Mandatory=$true)]
	[EnvironmentModules.EnvironmentModule]
	$Module
)

New-EnvironmentModuleFunction "Start-NotepadPlusPlus" $Module.Name { 	
	Start-Process -FilePath "${$Module.Name}\notepad++.exe" @args
}

$Module.AddAlias("npp", "Start-NotepadPlusPlus", "Use 'npp' to start Notepad++")

# # ------------------------
# # Static header
# # ------------------------
# 
# 
# $MODULE_NAME = $MyInvocation.MyCommand.ScriptBlock.Module.Name
# 
# # ------------------------
# # User content
# # ------------------------
# 
# $MODULE_SEARCHPATHS = @("C:\Program Files (x86)\Notepad++\")
# $MODULE_ROOT = Find-FirstFile "notepad++.exe" "" $MODULE_SEARCHPATHS
# 
# function SetModulePathsInternal([EnvironmentModules.EnvironmentModule] $eModule, [String] $eModuleRoot)
# {
# 	$eModule.AddAlias("npp", "Start-NotepadPlusPlus", "Use 'npp' to start Notepad++")
# 	$eModuleRoot = (Resolve-Path (Join-Path $eModuleRoot "..\"))
# 	
# 	return $eModule
# }
# 
# New-EnvironmentModuleFunction "Start-NotepadPlusPlus" $MODULE_NAME { 	
# 	Start-Process -FilePath "$MODULE_ROOT" @args
# }
# 
# # ------------------------
# # Static footer
# # ------------------------
# 
# Mount-EnvironmentModule -Name $MODULE_NAME -Root $MODULE_ROOT -Info $MyInvocation.MyCommand.ScriptBlock.Module -CreationDelegate ${function:SetModulePathsInternal} -DeletionDelegate ${Dismount-EnvironmentModule @args}