@{
    <#
        This is only required if you need to use the method PowerShellGet & PSDepend
        It is not required for PSResourceGet or ModuleFast (and will be ignored).
        See Resolve-Dependency.psd1 on how to enable methods.
    #>
    #PSDependOptions             = @{
    #    AddToPath  = $true
    #    Target     = 'output\RequiredModules'
    #    Parameters = @{
    #        Repository = 'PSGallery'
    #    }
    #}

    InvokeBuild                 = 'latest'
    PSScriptAnalyzer            = 'latest'
    Pester                      = 'latest'
    ModuleBuilder               = 'latest'
    # ModuleBuilder's runtime dependencies (Configuration → Metadata). Listed explicitly
    # because PSResourceGet 1.0.1 does not install transitive RequiredModules during the
    # bootstrap on a clean agent, which made `Import-Module ModuleBuilder` fail in CI with
    # "The required module 'Configuration' is not loaded".
    Configuration               = 'latest'
    Metadata                    = 'latest'
    ChangelogManagement         = 'latest'
    Sampler                     = 'latest'
    'Sampler.GitHubTasks'       = 'latest'

    # Runtime dependencies — must be present so Sampler's package_module_nupkg task
    # can bundle them alongside the module in the NuGet package.
    'Az.Resources'                    = '9.0.3'
    'Microsoft.Graph.Authentication'  = '2.36.0'


}

