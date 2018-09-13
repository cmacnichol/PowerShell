<#
    .Synopsis
        Add Users to Remote Computer Local Groups
   
    .DESCRIPTION
       Adbanced Function with Basic GUI to add users to remote computer local groups  
   
    .EXAMPLE

    .INPUTS
       Inputs to this cmdlet (if any)

    .OUTPUTS
       Output from this cmdlet (if any)       

    .NOTES
    
        Requires: Powershell 3.0


    Author          : Chris Macnichol
    Version         : 1.00 - Initial Build
    Version History :
    Created         : 05/17/2016
    Last updated    :
#>

function Add-RemoteUser
{
    [CmdletBinding(DefaultParameterSetName='Parameter Set 1', 
                  SupportsShouldProcess=$true, 
                  PositionalBinding=$false,
                  ConfirmImpact='Medium')]
    [Alias()]
    [OutputType([String])]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true, 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=0,
                   ParameterSetName='Parameter Set 1')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateCount(0,5)]
        [ValidateSet('sun', 'moon', 'earth')]
        [Alias('p1')] 
        $Param1

    )

    Begin
    {
    }
    Process
    {
        if ($pscmdlet.ShouldProcess('Target', 'Operation'))
        {
        }
    }
    End
    {
    }
}