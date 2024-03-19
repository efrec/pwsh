<#
.SYNOPSIS
Slice and display nested hashtables and arrays of hashtables. The function allows filters on keys and values, as well.

.DESCRIPTION
Format-Hashtable accepts an array of hashtables and will navigate into any nested hashtables or arrays of hashtables, up to a specified limit. You can skip a number of nesting levels; display only a fixed number of nested levels; and filter on the keys and values independently of one another.

.PARAMETER HashTable
The data as a hashtable or array of hashtables.

.PARAMETER FromDepth
The number of nesting levels to skip. Arrays are not considered nesting levels.

.PARAMETER ToDepth
The number of nesting levels to display. Levels after the ToDepth (+ FromDepth) are efficiently ignored.

.PARAMETER Depth
The current depth of nesting. This can be set by the user to display portions of the hashtable indented as though the previous recurrences were also displayed, but without displaying them. Otherwise, leave it alone; it's just used for recursion.

.PARAMETER KeyFilter
A [scriptblock] object with a valid `param` block that is passed IDictionaryEntry keys. It can do any other processing you like (e.g., `if ($key -eq 'Illegal!') { Write-Warning "Bad key: '$key'." }`), but should also return a true/false for the keys you want to include/exclude.

.PARAMETER ValueFilter
A [scriptblock] object with a valid `param` block that is passed IDictionaryEntry values. It can do any other processing you like (e.g., `if ($value -eq 'Oh no!') { Write-Warning "Bad value: '$value'." }`), but shouuld also return a true/false for the values you want to include/exclude.

.PARAMETER Indent
The character or string used as the basic indentation block. Defaults to a tab.

.EXAMPLE
 
# Output that makes you want to cry:
Get-Content .\unit-data.json | ConvertFrom-Json -AsHashtable -Depth 2 | % ToString

# result:
# System.Collections.Hashtable

# Output that you can read & can use:
Get-Content .\unit-data.json | ConvertFrom-Json -AsHashtable -Depth 2 | Format-Hashtable

# result:
# Roughneck (armbrawl)
# 	maxacc = 0.24
# 	blocking = False
# 	maxdec = 0.44
# 	energycost = 6200
# 	metalcost = 310
# 	buildtime = 13500
# 	canfly = True
# 	canmove = True
# 	category = ALL NOTLAND MOBILE WEAPON NOTSUB VTOL NOTSHIP NOTHOVER
# 	collide = True
# 	cruisealtitude = 100
# 	...
# ...

.EXAMPLE
$reusable = Format-Hashtable $data
# $reusable.GetType() => [string[]]

.EXAMPLE
# Skip the first hashtable and print the next two layers.
Format-Hashtable $data -FromDepth 1 -ToDepth 2

.EXAMPLE
Format-Hashtable $data -First 5 -KeyFilter {param($k) "$k" -in $keyList}

.NOTES
I think we all have felt the pain of PowerShell's data exploration and formatting. This function chooses to ignore, completely, the design patterns for formatting output in pwsh. Don't use it to do impressive things. Use it to get work done, which is what admins care about. Contributors could add paging; formatters; output options; and optimize the script's performance.
#>
function Format-HashTable {
	[CmdletBinding()]
	[OutputType([string[]])]
	param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[System.Collections.IDictionary[]] $HashTable,
		[Alias("From", "Skip", "SkipDepth")]
		[ValidateRange(0, [int]::MaxValue)] [int] $FromDepth = 0,
		[Alias("To", "First", "Limit", "MaxDepth")]
		[ValidateRange(0, [int]::MaxValue)] [int] $ToDepth = 100,
		[Alias("Current", "AtDepth")]
		[ValidateRange(0, [int]::MaxValue)] [int] $Depth = 0,
		[scriptblock] $KeyFilter,
		[scriptblock] $ValueFilter,
		[string] $Indent = "`t"
	)

	# Exit immediately, if we can.
	if ($Depth -gt $FromDepth + $ToDepth) { return }

	# Otherwise, iterate through the hashtables.
	$skipped = [Math]::Min($FromDepth, $Depth)
	$indents = $Depth - $skipped

	# Keys containing a nested hashtable are presented as mini-headers.
	$format = $PSStyle.Formatting.TableHeader
	$tamrof = $PSStyle.Reset

	# -- Loop with no filtering ----------------------------------------------------------------- #

	if (!$KeyFilter -and !$ValueFilter) {
		# Display the entire range of recurrences.
		foreach ($table in $HashTable) {
			foreach ($entry in $table.GetEnumerator()) {
				# When the value is another table, enter the next nesting level.
				if (
					$entry.Value -is [hashtable] -or
					$entry.Value -is [System.Collections.Specialized.OrderedDictionary] -or
					$entry.Value -is [hashtable[]] -or
					$entry.Value -is [System.Collections.Specialized.OrderedDictionary[]]
				) {
					if ($skipped -ge $FromDepth) {
						Write-Output "$($Indent * $indents)$format$($entry.Key)$tamrof"
					}
					# Enter the next recurrence.
					Format-HashTable -Depth ($Depth + 1) `
						-HashTable $entry.Value -Indent $Indent `
						-FromDepth $FromDepth -ToDepth $ToDepth
				}
				elseif ($skipped -ge $FromDepth) {
					Write-Output "$($Indent * $indents)$($entry.Key) = $($entry.Value ?? 'null')"
				}
			}
		}
		return
	}

	# -- Loop with filtering -------------------------------------------------------------------- #

	# Display only the key-value pairs that are not removed by the filter(s).
	# If a key is not filtered, but all of its values are, it is not displayed.
	# The $HashTable parameter is actually an array; we index into it first.
	foreach ($table in $HashTable) {
		foreach ($entry in $table.GetEnumerator()) {
			# When the value is another table, enter the next nesting level.
			# These values aren't tested against the ValueFilter, to simplify writing them.
			if (
				$entry.Value -is [hashtable] -or
				$entry.Value -is [System.Collections.Specialized.OrderedDictionary] -or
				$entry.Value -is [hashtable[]] -or
				$entry.Value -is [System.Collections.Specialized.OrderedDictionary[]]
			) {
				if ($skipped -ge $FromDepth) {
					Write-Output "$($Indent * $indents)$format$($entry.Key)$tamrof"
				}
				# Enter the next recurrence.
				Format-HashTable -Depth ($Depth + 1) `
					-HashTable $entry.Value -Indent $Indent `
					-FromDepth $FromDepth -ToDepth $ToDepth `
					-KeyFilter $KeyFilter -ValueFilter $ValueFilter
			}
			elseif (
				$skipped -ge $FromDepth -and
					(!$KeyFilter -or $KeyFilter.Invoke($entry.Key)) -and
					(!$ValueFilter -or $ValueFilter.Invoke($entry.Value))
			) {
				Write-Output "$($Indent * $indents)$($entry.Key) = $($entry.Value ?? 'null')"
			}
		}
	}

}
