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

.PARAMETER ExpandMatches
When a key or value is matched by the KeyFilter or the ValueFilter (respectively), show everything underneath that node, even if it is not also matching. This is default behavior; should rework this switch.

.PARAMETER AllMatches
When a key is not matched by the KeyFilter, keep searching; on any matching key below, ignore the filters on keys above that point.

.PARAMETER NilMatches
When a key that is not empty contains no remaining values after filtering, show it anyway.

.PARAMETER Indent
The character or string used as the basic indentation block. Defaults to a tab.

.EXAMPLE
# Output that kicks puppies:
Get-Content .\unit-data.json | ConvertFrom-Json -AsHashtable -Depth 2 | % ToString

# result:
# System.Collections.Hashtable

# Output that you can read:
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
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Management.Automation.OrderedHashtable[]] $HashTables,

        [Alias("From", "Skip", "SkipDepth")]
        [ValidateRange(0, [int]::MaxValue)] [int] $FromDepth = 0,
        [Alias("To", "First", "Limit", "MaxDepth")]
        [ValidateRange(0, [int]::MaxValue)] [int] $ToDepth = 100,
        [Alias("Current", "AtDepth")]
        [ValidateRange(0, [int]::MaxValue)] [int] $Depth = 0,

        [scriptblock] $KeyFilter,
        [scriptblock] $ValueFilter,

        [switch] $AllMatches,
        [switch] $ExpandMatches,
        [switch] $NilMatches,

        [ValidateSet("", " ", "  ", "   ", "    ", "`t")]
        [string] $Indent = "    "
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
                        Write-Output "$( $Indent * $indents )$format$( $entry.Key )$tamrof"
                    }
                    # Enter the next recurrence.
                    Format-HashTable -Depth ($Depth + 1) `
                        -HashTable $entry.Value -Indent $Indent `
                        -FromDepth $FromDepth -ToDepth $ToDepth
                }
                elseif ($skipped -ge $FromDepth) {
                    Write-Output "$( $Indent * $indents )$( $entry.Key ) = $( $entry.Value ?? 'null' )"
                }
            }
        }
        return
    }

    # -- Loop with filtering -------------------------------------------------------------------- #

    # Use the search method first, then format the hashtable without filters.

    Format-HashTable -HashTables $(
        Search-Tree-DepthFirst -HashTables $HashTables `
            -SkipNodes $FromDepth -KeepNodes $ToDepth -FromDepth $Depth `
            -NameFilter $KeyFilter -ValueFilter $ValueFilter `
            -IncludeEmptyNodes:$NilMatches -PreservePaths:$AllMatches -SortPaths -MergePaths
    ) -Indent $Indent -NilMatches:$NilMatches
}

# I give up. It's not that inefficient to separate the two functions.
# todo: make this at least semi-presentable

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

    # Return early.

    if ($KeepNodes -eq 0) { return }
    if ($FromDepth -gt $SkipNodes + $KeepNodes) { return }

    # We define several types of filter.
    # todo: key-value, set, and parent-child filters.

    $NameFilter ??= { return $true }  # todo: not passing to permissive filters.
    $ValueFilter ??= { return $true } # todo: requires handling null filter params.
    $collectionFilter = {
        param($item, $acceptNode, $skipValues)
        # Collections can contain subtrees, which sort-of have +0.5 depth.
        ($acceptNode -or $PreservePaths) -and (
            $item -is [hashtable] -or $item -is [hashtable[]] -or
            $item -is [System.Collections.Specialized.OrderedDictionary] -or
            $item -is [System.Collections.Specialized.OrderedDictionary[]] -or
            $item -is [ordered] -or $item -is [ordered[]]
        ) -or
        # And are otherwise simple collections of values.
        ($acceptNode -and !$skipValues -and $ValueFilter.Invoke($item))
    }

    # Iterate the top level of the tree, and access subtrees recursively.

    if (!$MergePaths -and $HashTables.Count -gt 1) {
        $tree = ([System.Management.Automation.OrderedHashtable[]] @{}) * $HashTables.Count
        $ii = 0
    }
    else {
        $tree = [ordered] @{}
    }

    $pruneTree = $true
    $skipping = $FromDepth -lt $SkipNodes
    $collapseSubnodes = $FromDepth -eq $SkipNodes + $KeepNodes

    Write-Verbose "Starting a depth-first search."

    foreach ($table in $HashTables) {
        $pruneTable = $true

        $subtree = @{}
        foreach ($node in $table.GetEnumerator()) {
            $acceptNode = $skipping -or $NameFilter.Invoke($node.Name)
            if (!$acceptNode -and !$PreservePaths) { continue }

            # -- Subtrees ----------------------------------------------------------------------- #

            # todo: there are more types to handle; eg how about invisibly handling enumerators?
            # todo: eg so we can prefilter: $hash.GetEnumerator() | ? Name -match '^cash' | fht

            if (
                $node.Value -is [hashtable] -or $node.Value -is [hashtable[]] -or
                $node.Value -is [System.Collections.Specialized.OrderedDictionary] -or
                $node.Value -is [System.Collections.Specialized.OrderedDictionary[]] -or
                $node.Value -is [ordered] -or $node.Value -is [ordered[]]
            ) {
                Write-Verbose "Accessing subnode ($( $node.Name ))."

                $params = $PSBoundParameters
                $params.Hashtables = $node.Value
                $params.FromDepth = $FromDepth + 1
                if ($acceptNode -and !$skipping) { [void]$params.Remove('NameFilter') } # ?

                $subnode = Search-Tree-DepthFirst @params

                # IncludeEmptyNodes only includes subnodes that were not empty before filtering:
                if ($subnode.Count -gt 0 -or ($IncludeEmptyNodes -and $node.Value.Count -gt 0)) {
                    Write-Verbose "Adding subnode ($( $node.Name ))."
                    $subtree.Add($node.Name, $subnode)
                    $pruneTable = $false
                }
            }

            # -- Collections -------------------------------------------------------------------- #

            # Collections also may contain subtrees; we cannot skip over them naively.
            # Non-subtree values in collections are filtered individually by the ValueFilter.
            # Subtrees have to be entered and checked when using PreservePaths, even if pruned.

            # todo: MergePaths on collections.

            elseif (
                $node.Value -isnot [string] -and 
                $node.Value.GetType().ImplementedInterfaces -contains [System.Collections.IEnumerable]
            ) {
                Write-Verbose "Accessing collection ($( $node.Name ))."

                $items = $node.Value | Where-Object {
                    Write-Verbose "Checking item: [$( $_.GetType().Name )] $_."
                    $collectionFilter.Invoke($_, $acceptNode, $skipping)
                } | ForEach-Object {
                    $collapseSubnodes -and $_ -is [hashtable] ? "$format$( $_.Name )$tamrof" : $_
                }

                if ($items.Count -gt 0 -or ($IncludeEmptyNodes -and $node.Value.Count -gt 0)) {
                    Write-Verbose "Adding collection: ($( $node.Name ))."
                    $subtree.Add($node.Name, $items)
                    $pruneTable = $false
                }
            }

            # -- Values ------------------------------------------------------------------------- #

            # Simple values (and strings) can be filtered and skipped naively.

            elseif (!$skipping -and $acceptNode) {
                Write-Verbose "Checking value: ($( $node.Name ), [$( $node.Value.GetType().Name )] $( $node.Value ))."

                if ($ValueFilter.Invoke($node.Value)) {
                    $subtree.Add($node.Name, $node.Value)
                    $pruneTable = $false
                }
            }
            else {
                Write-Verbose "Suppressed: ($( $node.Name ), [$( $node.Value.GetType().Name )] $( $node.Value ))."
            }
        }

        # Process the resulting subtree.

        if ($pruneTable) { continue }

        Write-Verbose "Adding subtree to result:`n$( $subtree.Keys )"
        $keys = $SortPaths ? ($subtree.Keys | Sort-Object) : $subtree.Keys

        if ($MergePaths -or $HashTables.Count -eq 1) {
            $keys | ForEach-Object { $tree.Add($_, $subtree.$_) }
        }
        else {
            $keys | ForEach-Object { $tree[$ii].Add($_, $subtree.$_) }
            $ii++
        }
        $subtree = @{}
    }

    # Process the resulting tree.

    if (!$MergePaths -and $HashTables.Count -gt 1) {
        $tree = $tree | Where-Object { $null -ne $_ -and $_.Count -gt 0 }
    }

    if ($tree.Count) { $pruneTree = $false }

    return $pruneTree ? [ordered] @{} : $tree
}


# -- Cleanup and etc ---------------------------------------------------------------------------- #

Set-Alias -Name 'fh' -Value Format-Hashtable
Set-Alias -Name 'fht' -Value Format-Hashtable
