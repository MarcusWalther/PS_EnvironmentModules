# ------------------------
# Static header
# ------------------------

$MODULE_NAME = $MyInvocation.MyCommand.ScriptBlock.Module.Name

# ------------------------
# User content
# ------------------------

$MODULE_ROOT = ".\"

function SetModulePathsInternal([EnvironmentModules.EnvironmentModule] $eModule, [String] $eModuleRoot)
{
    return $eModule
}

New-EnvironmentModuleFunction "Start-Cmd" $MODULE_NAME { return 42; }

# ------------------------
# Static footer
# ------------------------

Mount-EnvironmentModule -Name $MODULE_NAME -Root $MODULE_ROOT -Info $MyInvocation.MyCommand.ScriptBlock.Module -CreationDelegate ${function:SetModulePathsInternal} -DeletionDelegate ${Dismount-EnvironmentModule @args}