# start a remote console?
# stopping the console is done by connected to it and issuing a shutdown
# or killing the process.

set started_p 0
# check the status of started_p and possibly any existing console pids
if { [catch {open "/var/www/oacs-5-9-1/remote-console.started_p" r} f_id] } {
    #puts stdout "file doesn't exist"
    # File doesn't exist. So, leave started_p at default
} else {
    set started_p [read $f_id]
}
puts "started_p $started_p"
if { $started_p } {

    # See if a pid is already running
    set processes [exec ps aux]
    if { [string match {* tclsh /var/www/*} $processes] } {
	# remote process already running.
	#puts "already running"
    } else {
	exec /var/www/oacs-5-9-1/www/substation8/remote-console.tcl &
    }
}


    
    
