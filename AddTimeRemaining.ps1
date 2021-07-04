[CmdletBinding()]
param
(
  $InputFilePath
)

# Validate parameter
if ($InputFilePath -eq "")
{
  Write-Host "This script needs to be given a G code file to work with. One way to do this is by dragging & dropping a G code file onto the launcher script (AddTimeRemaining.cmd)."
}
elseif (!(Test-Path -Type Leaf $InputFilePath))
{
  Write-Host "Couldn't find a file called: $($InputFilePath)"
}
else
{
  # Inspect the file indicated, and make sure we have enough disk space (G code files can be quite large!)
  $FileInfo = [System.IO.FileInfo]::new($InputFilePath)

  $DriveInfo = [System.IO.DriveInfo]::new($FileInfo.Directory.Root)

  if ($DriveInfo.TotalFreeSpace -lt ($FileInfo.Length * 1.2))
  {
    Write-Host "Cannot process this file because there isn't enough free disk space to write out the updated file"
  }
  else
  {
    # Open the original (unmodified) file
    $Stream = $FileInfo.Open("Open")

    $TotalPrintTime = 0

    # Jump near the end of the file because we only need to find the last "time elapsed" comment
    if ($Stream.Length -gt 100000) { $Stream.Position = $Stream.Length - 100000 }

    # Attach a reader to the stream that will leave it open when disposed
    $Reader = [System.IO.StreamReader]::new($Stream, [System.Text.Encoding]::UTF8, $true, 131072, $true)

    # Scan the file for the largest "time elapsed", which should latch onto the final one that indicates total print time.
    Write-Host -NoNewLine "Scanning file..."

    $LineCount = 0

    while ($true)
    {
      $Line = $Reader.ReadLine()

      if ($Line -eq $null) { break }

      $LineCount++

      if ($LineCount % 10000 -eq 0) { Write-Host -NoNewLine "." }

      if ($Line.StartsWith(";TIME_ELAPSED:"))
      {
        $Elapsed = [decimal]$Line.Substring(14)

        if ($Elapsed -gt $TotalPrintTime) { $TotalPrintTime = $Elapsed }
      }
    }

    Write-Host ""

    if ($TotalPrintTime -eq 0)
    {
      Write-Host "Error: Unable to find print time estimates in this file (maybe it's not a G-code file?)"
    }
    else
    {
      Write-Host "Found total print time: $($TotalPrintTime) seconds"

      $TotalPrintTimeSpan = [System.TimeSpan]::FromSeconds($TotalPrintTime)

      Write-Host "=> $($TotalPrintTimeSpan)"

      # Go back to the start of the file, this time to process it
      $Stream.Position = 0

      $Reader = [System.IO.StreamReader]::new($Stream)

      # Find a temporary filename to which to write the updated file
      $ContainingDirectory = $FileInfo.Directory.FullName

      while ($true)
      {
        $NewTempName = [System.IO.Path]::Combine($ContainingDirectory, [Guid]::NewGuid().ToString("n"))

        if (!(Test-Path $NewTempName)) { break }
      }

      $Writer = [System.IO.StreamWriter]::new($NewTempName)

      # Process the contents
      Write-Host -NoNewLine "Processing file..."

      $AddedCommands = 0
      $LineCount = 0

      while ($true)
      {
        $Line = $Reader.ReadLine()

        if ($Line -eq $null) { break }

        $LineCount++

        if ($LineCount % 10000 -eq 0) { Write-Host -NoNewLine "." }

        $Writer.WriteLine($Line)

        if ($Line.StartsWith(";TIME_ELAPSED:"))
        {
          $Elapsed = [decimal]$Line.Substring(14)

          $Remaining = $TotalPrintTime - $Elapsed

          $Writer.WriteLine("M73 R{0:########0}", $Remaining)

          $AddedCommands++
        }
      }

      Write-Host ""

      # Rename the files, so that the original is moved out of the way and the new temporary file takes its name
      $Reader.Close()
      $Writer.Close()

      $TargetName = $FileInfo.FullName

      $OriginalFileName = $FileInfo.Name

      $OriginalFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFileName) + "-ORIGINAL" + [System.IO.Path]::GetExtension($OriginalFileName)
      $OriginalFileName = [System.IO.Path]::Combine($ContainingDirectory, $OriginalFileName)

      $NewFileInfo = [System.IO.FileInfo]::new($NewTempName)

      Write-Host "Added $($AddedCommands) commands, file size increased by $($NewFileInfo.Length - $FileInfo.Length) from $($FileInfo.Length) to $($NewFileInfo.Length) bytes"

      $FileInfo.MoveTo($OriginalFileName)
      $NewFileInfo.MoveTo($TargetName)
    }
  }
}

Pause