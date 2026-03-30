Describe 'Restore-GraphProperty' {
    BeforeAll {
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When the response ID matches the request ID (happy path)' {
        It 'copies the named property from the request into the response' {
            InModuleScope Omnicit.PIM {
                $request  = @{ roleDefinitionId = 'role-001'; roleDefinition = @{ displayName = 'Global Administrator' } }
                $response = @{ roleDefinitionId = 'role-001'; roleDefinition = $null }

                'roleDefinition' | Restore-GraphProperty -Request $request -Response $response

                $response.roleDefinition.displayName | Should -Be 'Global Administrator'
            }
        }

        It 'does not alter other keys in the response' {
            InModuleScope Omnicit.PIM {
                $request  = @{ roleDefinitionId = 'role-001'; roleDefinition = @{ displayName = 'Global Administrator' }; status = 'Provisioned' }
                $response = @{ roleDefinitionId = 'role-001'; roleDefinition = $null; status = 'Provisioned' }

                'roleDefinition' | Restore-GraphProperty -Request $request -Response $response

                $response.status | Should -Be 'Provisioned'
            }
        }
    }

    Context 'When an explicit -DataObject is supplied' {
        It 'copies the property from DataObject rather than Request' {
            InModuleScope Omnicit.PIM {
                $request    = @{ roleDefinitionId = 'role-001'; roleDefinition = @{ displayName = 'From Request' } }
                $dataObject = @{ roleDefinitionId = 'role-001'; roleDefinition = @{ displayName = 'From DataObject' } }
                $response   = @{ roleDefinitionId = 'role-001'; roleDefinition = $null }

                'roleDefinition' | Restore-GraphProperty -Request $request -Response $response -DataObject $dataObject

                $response.roleDefinition.displayName | Should -Be 'From DataObject'
            }
        }
    }

    Context 'When multiple property names are piped' {
        It 'restores each named property in turn' {
            InModuleScope Omnicit.PIM {
                $request  = @{
                    roleDefinitionId = 'role-001'
                    roleDefinition   = @{ displayName = 'Global Administrator' }
                    directoryScopeId = '/'
                    directoryScope   = @{ displayName = 'Root' }
                }
                $response = @{
                    roleDefinitionId = 'role-001'
                    roleDefinition   = $null
                    directoryScopeId = '/'
                    directoryScope   = $null
                }

                'roleDefinition', 'directoryScope' | Restore-GraphProperty -Request $request -Response $response

                $response.roleDefinition.displayName | Should -Be 'Global Administrator'
                $response.directoryScope.displayName | Should -Be 'Root'
            }
        }
    }

    Context 'When the response ID does not match the request ID' {
        It 'throws an error describing the mismatch' {
            InModuleScope Omnicit.PIM {
                $request  = @{ roleDefinitionId = 'role-001'; roleDefinition = @{ displayName = 'Global Administrator' } }
                $response = @{ roleDefinitionId = 'role-DIFFERENT'; roleDefinition = $null }

                { 'roleDefinition' | Restore-GraphProperty -Request $request -Response $response } |
                    Should -Throw '*does not match*'
            }
        }

        It 'does not mutate the response before throwing' {
            InModuleScope Omnicit.PIM {
                $request  = @{ roleDefinitionId = 'role-001'; roleDefinition = @{ displayName = 'Global Administrator' } }
                $response = @{ roleDefinitionId = 'role-DIFFERENT'; roleDefinition = $null }

                try { 'roleDefinition' | Restore-GraphProperty -Request $request -Response $response } catch {}

                $response.roleDefinition | Should -BeNullOrEmpty
            }
        }
    }
}
