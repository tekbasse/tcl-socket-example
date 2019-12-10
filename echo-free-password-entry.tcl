# Following from: https://wiki.tcl-lang.org/page/Echo-free+password+entry

# Read a single line of input from the terminal without echoing to the
# screen.  If Control-C is pressed, exit immediately.
#
proc tty_gets_no_echo {{prompt {}}} {
    if {$prompt!=""} {
	puts -nonewline $prompt
    }
    flush stdout
    global _tty_input _tty_wait tcl_platform
    if {$tcl_platform(platform)!="unix"} {
	# FIXME:  This routine only works on unix.  On other platforms, the
	# password is still echoed to the screen as it is typed.
	return [gets stdin]
    }
    set _tty_input {}
    set _tty_wait 0
    fileevent stdin readable _tty_read_one_character
    exec /bin/stty raw -echo <@stdin
    vwait ::_tty_wait
    fileevent stdin readable {}
    return $_tty_input
}
proc _tty_read_one_character {} {
    set c [read stdin 1]
    if {$c=="\n" || $c=="\003"} {
	exec /bin/stty -raw echo <@stdin
	puts ""
	if {$c=="\003"} exit
	incr ::_tty_wait
    } else {
	append ::_tty_input $c
    }
}
