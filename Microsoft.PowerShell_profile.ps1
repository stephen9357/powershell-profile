using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# This is an example profile for PSReadLine.
#
# This is roughly what I use so there is some emphasis on emacs bindings,
# but most of these bindings make sense in Windows mode as well.

Import-Module PSReadLine

#Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistoryNoDuplicates

#Set-PSReadLineOption -EditMode Emacs

# Clear background color of 'ls' command
$PSStyle.FileInfo.Directory="`e[34;1m"

# Searching for commands with up/down arrow is really handy.  The
# option "moves to end" is useful if you want the cursor at the end
# of the line while cycling through history like it does w/o searching,
# without that option, the cursor will remain at the position it was
# when you used up arrow, which can be useful if you forget the exact
# string you started the search on.
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# The built-in word movement uses character delimiters, but token based word
# movement is also very useful - these are the bindings you'd use if you
# prefer the token based movements bound to the normal emacs word movement
# key bindings.
Set-PSReadLineKeyHandler -Key Alt+d -Function ShellKillWord
Set-PSReadLineKeyHandler -Key Alt+Backspace -Function ShellBackwardKillWord
Set-PSReadLineKeyHandler -Key Alt+b -Function ShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+f -Function ShellForwardWord
Set-PSReadLineKeyHandler -Key Alt+B -Function SelectShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+F -Function SelectShellForwardWord


# Sometimes you enter a command but realize you forgot to do something else first.
# This binding will let you save that command in the history so you can recall it,
# but it doesn't actually execute.  It also clears the line with RevertLine so the
# undo stack is reset - though redo will still reconstruct the command line.
Set-PSReadLineKeyHandler -Key Alt+w `
                         -BriefDescription SaveInHistory `
                         -LongDescription "Save current line in history but do not execute" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
}

# Sometimes you want to get a property of invoke a member on what you've entered so far
# but you need parens to do that.  This binding will help by putting parens around the current selection,
# or if nothing is selected, the whole line.
Set-PSReadLineKeyHandler -Key 'Alt+(' `
                         -BriefDescription ParenthesizeSelection `
                         -LongDescription "Put parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
                         -ScriptBlock {
    param($key, $arg)

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($selectionStart -ne -1)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, '(' + $line.SubString($selectionStart, $selectionLength) + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, '(' + $line + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
    }
}

# Each time you press Alt+', this key handler will change the token
# under or before the cursor.  It will cycle through single quotes, double quotes, or
# no quotes each time it is invoked.
Set-PSReadLineKeyHandler -Key "Alt+'" `
                         -BriefDescription ToggleQuoteArgument `
                         -LongDescription "Toggle quotes on the argument under the cursor" `
                         -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $tokenToChange = $null
    foreach ($token in $tokens)
    {
        $extent = $token.Extent
        if ($extent.StartOffset -le $cursor -and $extent.EndOffset -ge $cursor)
        {
            $tokenToChange = $token

            # If the cursor is at the end (it's really 1 past the end) of the previous token,
            # we only want to change the previous token if there is no token under the cursor
            if ($extent.EndOffset -eq $cursor -and $foreach.MoveNext())
            {
                $nextToken = $foreach.Current
                if ($nextToken.Extent.StartOffset -eq $cursor)
                {
                    $tokenToChange = $nextToken
                }
            }
            break
        }
    }

    if ($tokenToChange -ne $null)
    {
        $extent = $tokenToChange.Extent
        $tokenText = $extent.Text
        if ($tokenText[0] -eq '"' -and $tokenText[-1] -eq '"')
        {
            # Switch to no quotes
            $replacement = $tokenText.Substring(1, $tokenText.Length - 2)
        }
        elseif ($tokenText[0] -eq "'" -and $tokenText[-1] -eq "'")
        {
            # Switch to double quotes
            $replacement = '"' + $tokenText.Substring(1, $tokenText.Length - 2) + '"'
        }
        else
        {
            # Add single quotes
            $replacement = "'" + $tokenText + "'"
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $extent.StartOffset,
            $tokenText.Length,
            $replacement)
    }
}

# This example will replace any aliases on the command line with the resolved commands.
Set-PSReadLineKeyHandler -Key "Alt+%" `
                         -BriefDescription ExpandAliases `
                         -LongDescription "Replace all aliases with the full command" `
                         -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $startAdjustment = 0
    foreach ($token in $tokens)
    {
        if ($token.TokenFlags -band [TokenFlags]::CommandName)
        {
            $alias = $ExecutionContext.InvokeCommand.GetCommand($token.Extent.Text, 'Alias')
            if ($alias -ne $null)
            {
                $resolvedCommand = $alias.ResolvedCommandName
                if ($resolvedCommand -ne $null)
                {
                    $extent = $token.Extent
                    $length = $extent.EndOffset - $extent.StartOffset
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $extent.StartOffset + $startAdjustment,
                        $length,
                        $resolvedCommand)

                    # Our copy of the tokens won't have been updated, so we need to
                    # adjust by the difference in length
                    $startAdjustment += ($resolvedCommand.Length - $length)
                }
            }
        }
    }
}

# `ForwardChar` accepts the entire suggestion text when the cursor is at the end of the line.
# This custom binding makes `RightArrow` behave similarly - accepting the next word instead of the entire suggestion text.
Set-PSReadLineKeyHandler -Key RightArrow `
                         -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
                         -LongDescription "Move cursor one character to the right in the current editing line and accept the next word in suggestion when it's at the end of current editing line" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
    }
}

function uptime {
    $LastBootTime = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty LastBootUpTime
    $FormattedBootTime = $LastBootTime.toString("dddd, MMMM dd, yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    Write-Host "Last boot time: $FormattedBootTime"
    $uptime = (Get-Date) - $LastBootTime
    Write-Host "Uptime: $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes, $($uptime.Seconds) seconds."
}

Import-Module -Name PSFzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
$env:FZF_DEFAULT_OPTS="--layout=reverse --height=40%"
