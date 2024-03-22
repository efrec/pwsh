<#
.SYNOPSIS
Slice and display nested hashtables and arrays of hashtables. The function allows filters on keys and values, as well.

.DESCRIPTION
Format-Hashtable accepts an array of hashtables and will navigate into any nested hashtables or arrays of hashtables, up to a specified limit. You can skip a number of nesting levels; display only a fixed number of nested levels; and filter on the keys and values independently of one another.

.PARAMETER HashTables
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

.PARAMETER ShowKeysBelow
When a key or value is matched by the KeyFilter or the ValueFilter (respectively), show everything underneath that node, even if it is not also matching. I think this is the functionality people would expect; not sure.

.PARAMETER ShowKeysAbove
When a key is not matched by the KeyFilter, keep searching; on any matching key below, ignore the filters on keys above that point. Like ShowKeysBelow, this may be what users expect from this function.

.PARAMETER ShowEmptyKeys
When a key that is not empty contains no remaining values after filtering, show it anyway.

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

.EXAMPLE
# Skip the first hashtable layer and print the next two layers.
Format-Hashtable $data -FromDepth 1 -ToDepth 2

.EXAMPLE
# One nice way to write the filters is with the param() block:
Format-Hashtable $data -ToDepth 5 -KeyFilter {param($k) "$k" -in $keyList}

.EXAMPLE
# A shorter way to write the filters is to use $args[0] (or just $args in some cases).
Format-HashTable $data.units -Skip 2 -ValueFilter {$args[0] -is [long]} -ShowKeysAbove

.NOTES
I think we all have felt the pain of PowerShell's data exploration and formatting. This function chooses to ignore most design patterns for formatting output in pwsh. Don't use it to do impressive things. Use it to get work done, maybe.

These two functions (Format-HashTable and Search-Tree-DepthFirst) were written separately for different but related reasons and don't quite work together, yet. For example, FHT doesn't sort keys, but STDF does; so when a filter is passed to FHT, suddenly your keys are returned sorted. Oy vey.
#>
function Format-HashTable {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [System.Management.Automation.OrderedHashtable[]] $HashTables,

        [Alias("From", "Skip", "SkipDepth")]
        [ValidateRange(0, [int]::MaxValue)] [int] $FromDepth = 0,
        [Alias("To", "First", "Limit", "MaxDepth")]
        [ValidateRange(0, [int]::MaxValue)] [int] $ToDepth = 100,
        [Alias("Current", "AtDepth")]
        [ValidateRange(0, [int]::MaxValue)] [int] $Depth = 0,

        [scriptblock] $KeyFilter,
        [scriptblock] $ValueFilter,

        [switch] $ShowKeysBelow,
        [switch] $ShowKeysAbove,
        [switch] $ShowEmptyKeys,

        [string] $Indent = "`t"
    )

    # Exit immediately, if we can.
    if ($ToDepth -lt 1 -or $Depth -gt $FromDepth + $ToDepth) { return }

    # Otherwise, iterate through the hashtables.
    $skipped = [Math]::Min($FromDepth, $Depth)
    $indents = $Depth - $skipped

    # Keys containing a nested hashtable are presented as mini-headers.
    $format = $PSStyle.Formatting.TableHeader
    $tamrof = $PSStyle.Reset

    # -- Loop with no filtering ----------------------------------------------------------------- #

    if (!$KeyFilter -and !$ValueFilter) {
        # Display the entire range of recurrences.
        foreach ($table in $HashTables) {
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

    # Use the search method first, then format the hashtable without filters.

    Search-Tree-DepthFirst -HashTables $HashTables `
        -SkipNodes $FromDepth -KeepNodes $ToDepth -FromDepth $Depth `
        -NameFilter $KeyFilter -ValueFilter $ValueFilter `
        -IncludeEmptyNodes:$ShowEmptyKeys -PreservePaths:$ShowKeysAbove -SortPaths | Format-HashTable
}

# I give up. It's not that inefficient to separate the two functions.

function Search-Tree-DepthFirst {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [System.Management.Automation.OrderedHashtable[]] $HashTables,

        [int] $SkipNodes = 0,
        [int] $KeepNodes = 100,
        [int] $FromDepth = 0,

        [scriptblock] $NameFilter,
        [scriptblock] $ValueFilter,

        # Keep nodes containing only collections or subnodes which are empty after filtering.
        # Does not apply to individual values, nor to collections or subnodes that are already empty.
        [switch] $IncludeEmptyNodes,

        # Keep filtered nodes that contain non-filtered subnodes with non-filtered values.
        # This flag will not cause the search to go beyond its maximum depth, however.
        [switch] $PreservePaths,

        # Merge each collection of nested tables (if any) into a subnode, instead.
        # This may cause data loss if misused. Be careful when you pass this flag.
        [switch] $MergePaths,

        # Sort the resulting tables alphabetically. Collections have their order preserved.
        [switch] $SortPaths
    )

    # Guard against deep accesses.

    if ($KeepNodes -eq 0) { return }
    if ($FromDepth -gt $SkipNodes + $KeepNodes) { return }

    $NameFilter ??= { return $true }
    $ValueFilter ??= { return $true }
    $collectionFilter = {
        param($coll, $keep)
        $coll | Where-Object {
            # "There has to be a better way"
            $_ -is [hashtable] -or
            $_ -is [hashtable[]] -or
            $_ -is [System.Collections.Specialized.OrderedDictionary] -or
            $_ -is [System.Collections.Specialized.OrderedDictionary[]] -or
            $_ -is [System.Management.Automation.OrderedHashtable] -or
            $_ -is [System.Management.Automation.OrderedHashtable[]] -or
            ($keep -and $ValueFilter.Invoke($_))
        }
    }

    # Iterate the top level of the tree. Access subtrees recursively.

    if (!$MergePaths -and $HashTables.Count -gt 1) {
        $tree = ([System.Management.Automation.OrderedHashtable[]] @{}) * $HashTables.Count
        $ii = 0
    }
    else {
        $tree = [ordered] @{}
    }

    $pruneTree = $true
    $skipping = $SkipNodes -gt $FromDepth

    Write-Verbose "Starting the depth-first search."

    foreach ($table in $HashTables) {
        $pruneTable = $true

        $subtree = @{}
        foreach ($node in $table.GetEnumerator()) {
            $pruneNode = !$NameFilter.Invoke($node.Name) # "Name" can be anything? Or is Key => ToString ?
            if ($pruneNode -and !$PreservePaths) { continue }

            # -- Subtrees ----------------------------------------------------------------------- #

            if (
                $node.Value -is [hashtable] -or
                $node.Value -is [hashtable[]] -or
                $node.Value -is [System.Collections.Specialized.OrderedDictionary] -or
                $node.Value -is [System.Collections.Specialized.OrderedDictionary[]] -or
                $node.Value -is [System.Management.Automation.OrderedHashtable] -or
                $node.Value -is [System.Management.Automation.OrderedHashtable[]]
            ) {
                Write-Verbose "Accessing subnode ($($node.Name))."

                $params = $PSBoundParameters
                $params.Hashtables = $node.Value
                $params.FromDepth = $FromDepth + 1
                if (!$pruneNode) { [void]$params.Remove('NameFilter') }

                $subnode = Search-Tree-DepthFirst @params

                # IncludeEmptyNodes only includes subnodes that were not empty before filtering:
                if ($subnode.Count -or ($IncludeEmptyNodes -and $node.Value.Count -gt 0)) {
                    $subtree.Add($node.Name, $subnode)
                    $pruneTable = $false
                }
            }

            # -- Collections -------------------------------------------------------------------- #

            # Collections also may contain subtrees; we cannot skip over them naively.
            # Non-subtree values in collections are filtered individually by the ValueFilter.

            elseif (
                $node.Value.GetType() | ForEach-Object {
                    $_ -ne [string] -and
                    $_.ImplementedInterfaces -contains [System.Collections.IEnumerable]
                }
            ) {
                Write-Verbose "Accessing collection ($($node.Name))."

                $values = $node.Value | Where-Object { $collectionFilter.Invoke($_, !$skipping) }

                if ($values.Count -or ($IncludeEmptyNodes -and $node.Value.Count -gt 0)) {
                    $subtree.Add($node.Name, $values)
                    $pruneTable = $false
                }
            }

            # -- Values ------------------------------------------------------------------------- #

            # Simple values (and strings) can be filtered and skipped naively.

            elseif (!$skipping -and !$pruneNode) {
                Write-Verbose "Checking value ($($node.Name), [$($node.Value.GetType() -replace '^.*\.')] $($node.Value))."

                if ($ValueFilter.Invoke($node.Value)) {
                    $subtree.Add($node.Name, $node.Value)
                    $pruneTable = $false
                }
            }

            # ----------------------------------------------------------------------------------- #
        }

        # Process the resulting subtree.

        if ($pruneTable) { continue }

        Write-Verbose "Adding subtree to result:`n$subtree"

        $keys = $SortPaths ? ($subtree.Keys | Sort-Object) : $subtree.Keys

        if ($MergePaths -or $HashTables.Count -eq 1) {
            $keys | ForEach-Object { $tree[$_] = $subtree[$_] }
        }
        else {
            $keys | ForEach-Object { $tree[$ii][$_] = $subtree[$_] }
            $ii++
        }
        $subtree = $null
    }

    # Process the resulting tree.

    if (!$MergePaths -and $HashTables.Count -gt 1) { $tree = $tree | Where-Object { $null -ne $_ } }

    if ($tree.Count) { $pruneTree = $false }

    return $pruneTree ? '' : $tree
}
