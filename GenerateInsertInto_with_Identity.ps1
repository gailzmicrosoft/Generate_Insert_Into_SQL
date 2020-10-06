
#======================================================================================================================#
#                                                                                                                      #                                                                                                                      #
#  This utility was developed on a best effort basis                                                                   #
#  to aid effort to migrate into Azure Synapse and then Optimize the Design for best performance.                      #                                                       #
#  It is not an officially supported Microsoft application or tool.                                                    #
#                                                                                                                      #
#  The utility and any script outputs are provided on "AS IS" basis and                                                #
#  there are no warranties, express or implied, including, but not limited to implied warranties of merchantability    #
#  or fitness for a particular purpose.                                                                                #
#                                                                                                                      #                    
#  The utility is therefore not guaranteed to generate perfect code or output. The output needs carefully reviewed.    #
#                                                                                                                      #
#                                       USE AT YOUR OWN RISK.                                                          #
#  Author: Gaiye "Gail" Zhou                                                                                           #
#  October, 2020                                                                                                        #
#                                                                                                                      #
#                                                                                                                      #
#======================================================================================================================#
#
#==========================================================================================================
# Functions Start here 
#==========================================================================================================
#
# Capture Time Difference and Format time parts into easy to read or display formats. 
Function GetDuration() {
    [CmdletBinding()] 
    param( 
        [Parameter(Position = 1, Mandatory = $true)] [datetime]$StartTime, 
        [Parameter(Position = 1, Mandatory = $true)] [datetime]$FinishTime
    ) 

    $ReturnValues = @{ }

    $Timespan = (New-TimeSpan -Start $StartTime -End $FinishTime)

    $Days = [math]::floor($Timespan.Days)
    $Hrs = [math]::floor($Timespan.Hours)
    $Mins = [math]::floor($Timespan.Minutes)
    $Secs = [math]::floor($Timespan.Seconds)
    $MSecs = [math]::floor($Timespan.Milliseconds)

    if ($Days -ne 0) {

        $Hrs = $Days * 24 + $Hrs 
    }

    $DurationText = '' # initialize it! 

    if (($Hrs -eq 0) -and ($Mins -eq 0) -and ($Secs -eq 0)) {
        $DurationText = "$MSecs milliseconds." 
    }
    elseif (($Hrs -eq 0) -and ($Mins -eq 0)) {
        $DurationText = "$Secs seconds $MSecs milliseconds." 
    }
    elseif ( ($Hrs -eq 0) -and ($Mins -ne 0)) {
        $DurationText = "$Mins minutes $Secs seconds $MSecs milliseconds." 
    }
    else {
        $DurationText = "$Hrs hours $Mins minutes $Secs seconds $MSecs milliseconds."
    }

    $ReturnValues.add("Hours", $Hrs)
    $ReturnValues.add("Minutes", $Mins)
    $ReturnValues.add("Seconds", $Secs)
    $ReturnValues.add("Milliseconds", $MSecs)
    $ReturnValues.add("DurationText", $DurationText)

    return $ReturnValues 

}

Function GetColumnList($FileNameFullPath) {
    $myColumnList = @{}

    $CreatTableFlag = '0'
    $WithFlag = '0'
    $i = 0
    ForEach ($line in Get-Content $FileNameFullPath) {
        if ($line -match "CREATE TABLE ") 
        {
            $CreatTableFlag = '1'
            Continue

        }
        if ($line.ToUpper() -eq "WITH") {
            $WithFlag = '1'
        }
    
        if ( ($CreatTableFlag -eq '1') -and ($WithFlag -eq '0')) 
        {
            $line = $line.Replace(',', '')
            $line = $line.Replace('[', '')
            $line = $line.Replace(']', '')
    
            $stringParts = $line.split(" ")
            $partsCount = $stringParts.Count
            $columnName = $stringParts[0]
            if (($partsCount -ge 3) -and ( $columnName -ne '(') -and ($columnName -ne ')') -and ( $WithFlag -eq '0')  )  
            {
                $i++ 
                $columnName = $stringParts[0]
                $myColumnList.Add($i, $columnName) 

            }

        }
    }
    Return $myColumnList 
}


######################################################################################
########### Main Program 
#######################################################################################


$ProgramStartTime = (Get-Date)
Write-Host " " 
Write-Host "Program started at " $ProgramStartTime -ForegroundColor Green 

$ScriptPath = Split-Path $MyInvocation.MyCommand.Path -Parent
Set-Location -Path $ScriptPath

$cfgFilePath = Read-Host -prompt "Enter the Config File Path or press 'Enter' to accept the default [$($ScriptPath)]"
if([string]::IsNullOrEmpty($cfgFilePath)) {
    $cfgFilePath = $ScriptPath
}


# CSV Configuration File

$defaultTablesCfgFile = "Heap_to_Target.csv"
$tablesCfgFile = Read-Host -prompt "Enter the COPY INTO Tables Config Name or press 'Enter' to accept the default [$($defaultTablesCfgFile)]"
if([string]::IsNullOrEmpty($tablesCfgFile)) {
    $tablesCfgFile = $defaultTablesCfgFile
}
$tablesCfgFileFullPath = join-path $cfgFilePath $tablesCfgFile
if (!(test-path $tablesCfgFileFullPath )) {
    Write-Host "Could not find Config File: $tablesCfgFileFullPath " -ForegroundColor Red
    break 
}

$csvTablesCfgFile = Import-Csv $tablesCfgFileFullPath

ForEach ($csvItem in $csvTablesCfgFile) 
{
    $Active = $csvItem.Active
    If ($Active -eq "1") 
    {
        $SourceSchema = $csvItem.SourceSchema
        $TargetSchema = $csvItem.TargetSchema
        $SourceTable = $csvItem.SourceTable
        $TargetTable = $csvItem.TargetTable
        $TruncateTable = $csvItem.TruncateTable
        $IdentityInsert = $csvItem.IdentityInsert
        $InputFolder = $csvItem.InputFolder
        $OutputFolder = $csvItem.OutputFolder
    
        # Use the TARGET Table .sql DDL as input to generate Heap to Target "Insert Into" T-SQL Statements
        $InputFileName = $TargetSchema + "." + $TargetTable + ".sql"
        $InputFileFullPath =  $InputFolder  + "\" +  $InputFileName

        # All the Insert Into Statements .sql file will start with InsertInto_schemaName.TableName.sql" 
        $OutputFileName = "InsertInto_" + $TargetSchema + "." + $TargetTable + ".sql"
        $OutputFileFullPath =  $OutputFolder  + "\" +  $OutputFileName

        if (!(test-path $InputFileFullPath))
        {
        
            Write-Host "File $InputFileFullPath  does not exist." -ForegroundColor red 
            Continue # process next file 
        }
      
        if (!(test-path $OutputFolder ))
        {
            New-Item -ItemType Directory -Force -Path $OutputFolder| Out-Null
            Write-Host "New Output Directory $OutputFolder is created." -ForegroundColor Yellow
        }

        if (test-path  $OutputFileFullPath ) {
            Write-Host "Previous File will be overwritten: " $OutputFileFullPath -ForegroundColor Yellow
            Remove-Item $OutputFileFullPath  -Force
        }

        Write-Host "IdentityInsert: $IdentityInsert " -ForegroundColor Cyan
        Write-Host "Check Content in Output File $OutputFileFullPath." -ForegroundColor Cyan

        $CodeGenerationTime = (Get-Date)
        "-- File Name: " + $OutputFileName >> $OutputFileFullPath
        "-- Code Generated at " + $CodeGenerationTime >> $OutputFileFullPath
        " " >> $OutputFileFullPath

        If ($TruncateTable.ToUpper() -eq 'YES')
        {
            "TRUNCATE TABLE " + $TargetSchema + "." + $TargetTable >> $OutputFileFullPath
            " " >> $OutputFileFullPath
        }
       
        If ($IdentityInsert.ToUpper() -eq 'YES')
        {
            $TableColumns = GetColumnList $InputFileFullPath

            "SET IDENTITY_INSERT " +   $TargetSchema + "." + $TargetTable + " ON "  >>  $OutputFileFullPath
            " " >>  $OutputFileFullPath

            "INSERT INTO " + $TargetSchema + "." + $TargetTable  >> $OutputFileFullPath
            "(" >>  $OutputFileFullPath

            $columCount = $TableColumns.Count
            For ($i=1; $i -le $columCount; $i++)
            {
                if ($i -eq ($columCount))
                {
                    "  " +   $TableColumns[$i] >> $OutputFileFullPath
                }
                else 
                {
                    "  " +   $TableColumns[$i] + "," >> $OutputFileFullPath
                }
             
            }
            ")" >>  $OutputFileFullPath
            "SELECT " >> $OutputFileFullPath
            For ($i=1; $i -le $columCount; $i++)
            {
                if ($i -eq ($columCount))
                {
                    "  " +   $TableColumns[$i] >> $OutputFileFullPath
                }
                else 
                {
                    "  " +   $TableColumns[$i] + "," >> $OutputFileFullPath
                }
             
            }
            "FROM " + $SourceSchema + "." + $SourceTable >> $OutputFileFullPath

            " " >>  $OutputFileFullPath
            "SET IDENTITY_INSERT " +   $TargetSchema + "." + $TargetTable + " OFF "  >>  $OutputFileFullPath

        }
        else 
        {
            "INSERT INTO " + $TargetSchema + "." + $TargetTable  >> $OutputFileFullPath
            "SELECT * FROM " + $SourceSchema + "." + $SourceTable >> $OutputFileFullPath
            " " >>  $OutputFileFullPath

        }

    }

}



$ProgramFinishTime = (Get-Date)

$ProgDuration = GetDuration  -StartTime  $ProgramStartTime -FinishTime $ProgramFinishTime

Write-Host "Total time runing this program: " $ProgDuration.DurationText 
Write-Host "Done. Completed at " (Get-Date)   -ForegroundColor Green 
Write-Host "^!^ Have a great day!" -ForegroundColor Cyan