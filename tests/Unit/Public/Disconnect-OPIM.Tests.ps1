Describe 'Disconnect-OPIM' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called successfully' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Disconnect-AzAccount {}
        }

        It 'calls Disconnect-MgGraph' {
            Disconnect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 1 -Scope It
        }

        It 'calls Disconnect-AzAccount' {
            Disconnect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-AzAccount -Times 1 -Scope It
        }

        It 'produces no output' {
            $Result = Disconnect-OPIM
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When Disconnect-MgGraph throws (not connected)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph { throw 'Not connected' }
            Mock -ModuleName Omnicit.PIM Disconnect-AzAccount {}
        }

        It 'does not produce a terminating error' {
            { Disconnect-OPIM } | Should -Not -Throw
        }

        It 'still calls Disconnect-AzAccount despite the Disconnect-MgGraph error' {
            Disconnect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-AzAccount -Times 1 -Scope It
        }
    }
}
