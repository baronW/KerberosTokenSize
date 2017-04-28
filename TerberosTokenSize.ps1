<#
Date: 28/04/2107
Use:  Get all users Token Size
#>
function Split-array 
{

<#  
  .SYNOPSIS   
    Split an array 
  .PARAMETER inArray
   A one dimensional array you want to split
  .EXAMPLE  
   Split-array -inArray @(1,2,3,4,5,6,7,8,9,10) -parts 3
  .EXAMPLE  
   Split-array -inArray @(1,2,3,4,5,6,7,8,9,10) -size 3
#> 

  param($inArray,[int]$parts,[int]$size)
  
  if ($parts) {
    $PartSize = [Math]::Ceiling($inArray.count / $parts)
  } 
  if ($size) {
    $PartSize = $size
    $parts = [Math]::Ceiling($inArray.count / $size)
  }

  $outArray = @()
  for ($i=1; $i -le $parts; $i++) {
    $start = (($i-1)*$PartSize)
    $end = (($i)*$PartSize) - 1
    if ($end -ge $inArray.count) {$end = $inArray.count}
    $outArray+=,@($inArray[$start..$end])
  }
  return ,$outArray

}
#gets all Ad Groups then splits them into a usable size
$ADGroups = Get-ADGroup -Filter * -Properties memberof
$split = Split-array -inArray $ADGroups -size 200
$ADGroupsHash = @{} 
$b = 0

#creates a hashtable from the Groups to speed up the indexing
#this is split into groups od 200 for some reason this makes it go faster
foreach ($S in $split){
    $ADGroupsHash0 = @{}
    $S | %{$ADGroupsHash0 += @{$_.DistinguishedName=$_}} #$(if (($_.GroupScope -eq 'Global') -or ($_.GroupScope -eq 'Universal')){8}elseif($_.GroupScope -eq 'DomainLocal'){40})}}
    $b++
    Write-Host $b -ForegroundColor Green
    $ADGroupsHash += $ADGroupsHash0
}

<#this genorates a hash table that looks like this. 
Note that the the GroupSet for each group contains all the groups that you are a member of if you are a member of that group INCLUDING the original group

Keys                    Values
DistinguishedName1      Hashtable AKA GroupSet (If you are in this group you are in all of these groups)
                        Keys                    Values
                        DistinguishedName1      TokenSize
                        DistinguishedName2      TokenSize
                        DistinguishedName3      TokenSize
                        DistinguishedName4      TokenSize
                        DistinguishedName5      TokenSize
                        DistinguishedName6      TokenSize

DistinguishedName8      Hashtable
                        DistinguishedName8      TokenSize  
                        DistinguishedName9      TokenSize
#>

$count = 0
$MassiveHash = @{}

foreach ($S in $split){
    $MassiveHash0 = @{}
    foreach ($Group in $S){
        $Value = if(($Group.GroupScope -eq 'Global') -or ($Group.GroupScope -eq 'Universal')){8}elseif($Group.GroupScope -eq 'DomainLocal'){40}else{0}
        $GroupSet = @{$Group.DistinguishedName = $Value}
        
        [array]$NextLevel = $ADGroupsHash.$($Group.DistinguishedName).MemberOf
        
        while ($NextLevel.Count -gt 0){
            $ThisLevel = $NextLevel | Sort-Object | Get-Unique
            $NextLevel = @()
            foreach ($GR in $ThisLevel){ 
                if (!($GroupSet.$GR)){
                    $GRObject = $ADGroupsHash.$GR
                    $Value = if(($GRObject.GroupScope -eq 'Global') -or ($GRObject.GroupScope -eq 'Universal')){8}elseif($GRObject.GroupScope -eq 'DomainLocal'){40}else{0}
                    $GroupSet+= @{$GR=$Value}
                    $NextLevel += $GRObject.MemberOf
                }
            }
        }
        $MassiveHash0 += @{$Group.DistinguishedName=$GroupSet}
    }
    $count++
    Write-Host $count
    $MassiveHash += $MassiveHash0
}

#$MassiveHash = Import-Clixml "\\wn0Packages\Packages\_development\PoSH\ADBits\MassiveHash.xml"
#gets all the users combinest the group set for all their groups (removing duplicates) then sums the values from the resulting UserHash
$adusers = Get-ADUser -Filter * -Properties MemberOf | Select-Object -Property MemberOf,SamAccountName,name
$CountDown = $adusers.count
#$TokenSizes = foreach ($User in $($adusers | Get-Random -Count 200)){
$TokenSizes = foreach ($User in $adusers){

    [array]$UserGroups = $User | Select-Object -ExpandProperty memberof
    #for some reason domain users is not included in a users 'memberof' property
    [array]$domainUsers = 'CN=Domain Users,CN=Users,DC=AD,DC=CCDHB,DC=HEALTH,DC=NZ'
    $UserGroups = $UserGroups + $domainUsers

    $UserHash = @{}

    foreach ($G in $UserGroups){
        $keys = $MassiveHash.$G.keys
        $mew = $keys
        $UserKeys = $UserHash.Keys
        $EasyMerge = $true
        foreach($K in $keys){
            if ($UserKeys -contains $K){
                $EasyMerge = $false
                continue
            }
        }

        if ($EasyMerge){
            $UserHash += $MassiveHash.$G
        }
        else{
            foreach($K in $keys){
                if ($UserKeys -notcontains $K){
                    $UserHash += @{$K=$MassiveHash.$G.$K}
                }
            }
        }
    }

    $size = $(($UserHash.Values | Measure-Object -Sum).sum + 1200)

    $output = New-Object -TypeName psobject
    $output | Add-Member -Name 'Name' -MemberType NoteProperty -Value $User.name
    $output | Add-Member -Name 'User ID' -MemberType NoteProperty -Value $User.SamAccountName
    $output | Add-Member -Name 'Token Size' -MemberType NoteProperty -Value $size
    $output 
    $CountDown--
    write-host $CountDown Green
}

$TokenSizes | Export-Csv -Path C:\Temp\R\TokenSize.csv -Force -NoTypeInformation


#spam