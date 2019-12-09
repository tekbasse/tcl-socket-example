#!/usr/bin/env tclsh
# Pseudo-telnet client.

proc telnet {{server localhost} {port telnet}} {
    set sock [socket $server $port]
    fconfigure $sock -buffering none -blocking 0 \
            -encoding binary -translation crlf -eofchar {}
    fconfigure stdout -buffering none
    #fileevent $sock readable [list initEvents $sock]
    fileevent $sock readable [list fromServer $sock]
    fileevent stdin readable [list toServer $sock]
    global closed
    vwait closed($sock)
    unset closed($sock)
}

proc initEvents {sock} {
    puts -nonewline [read $sock 4096]
    fileevent $sock readable [list fromServer $sock]
    fileevent stdin readable [list toServer $sock]
}

proc toServer {sock} {
    if {[gets stdin line] >= 0} {
        puts $sock $line
    } else {
        disconnect $sock
    }
}

proc fromServer {sock} {
    set data x
    while {[string length $data]} {
        set data [read $sock 4096]
        if {[eof $sock]} {
            disconnect $sock
            return
        }
        if {[string length $data]} {
            while 1 {
                set idx [string first \xff $data]
                if {$idx < 0} {
                    break
                }
                write [string range $data 0 [expr {$idx-1}]]
                set byte [string index $data [expr {$idx+1}]]
                incr idx 2
                if {$byte < "\xf0"} {
                    write \xf0$byte
                } elseif {$byte == "\xff"} {
                    write \xf0
                } else {
                    binary scan $byte H2 op
                    protocol $sock $op
                }
                set data [string range $data $idx end]
            }
            puts -nonewline stdout $data
        }
    }
}

proc disconnect {sock} {
    global closed
    close $sock
    set closed($sock) 1
}

proc write string {
    puts -nonewline stdout [encoding convertfrom iso8859-1 $string]
}

proc protocol {sock op} {
    upvar 1 data data idx idx
    switch $byte {
        f0 {# SE
        }
        f1 {# NOP
            return
        }
        f2 {# DATA MARK
        }
        f3 {# BRK
        }
        f4 {# IP
        }
        f5 {# AO
        }
        f6 {# AYT
            puts $sock {[YES]}
        }
        f7 {# EC
            write \u007f
        }
        f8 {# EL
            write \u0019
        }
        f9 {# GA
        }
        fa {# SB
            # Should search forward for IAC SE (\xff\xf0) but since
            # we refuse to turn on any extension features, we should
            # never encounter any such things.
        }
        fb {# WILL
            # Attempt to negotiate; refuse!
            set byte [string index $data $idx]
            puts -nonewline $sock \xff\xfe$byte
            incr idx
        }
        fc {# WON'T
            incr idx
        }
        fd {# DO
            # Attempt to negotiate; refuse!
            set byte [string index $data $idx]
            puts -nonewline $sock \xff\xfc$byte
            incr idx
        }
        fe {# DON'T
            incr idx
        }
    }
}

if {[llength $argv] > 2} {
    puts stderr "wrong # args: should be \"telnet ?hostname? ?port?\""
    puts stderr "\thostname defaults to \"localhost\""
    puts stderr "\tport defaults to the telnet port, and may be specified"
    puts stderr "\teither by name or by number"
} else {
    eval telnet $argv
}
exit

