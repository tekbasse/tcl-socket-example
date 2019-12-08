# Following from https://www.tcl-lang.org/man/tcl/TclCmd/socket.htm
#EXAMPLES
#Here is a very simple time server:
proc Server {startTime channel clientaddr clientport} {
    puts "Connection from $clientaddr registered"
    set now [clock seconds]
    puts $channel [clock format $now]
    puts $channel "[expr {$now - $startTime}] since start"
    close $channel
}

socket -server [list Server [clock seconds]] 9900
vwait forever
