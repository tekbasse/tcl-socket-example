#!/usr/bin/env tclsh
# Pseudo-telnet server.  Includes basic auth, but no separate identities
# or proper multi-threaded operation, so whoever runs this had better
# trust those he gives identities/passwords to and they had better trust
# each other too.  Note this script does not support command-line arguments.

## The names of this array are IP addresses of hosts that are not permitted
## to connect to any of our services.  Admin account(s) can change this
## at run-time, though this info is not maintained across whole-server shutdowns.
array set denyHosts {}

## Create a server on the given port with the given name/password map
## and the given core interaction handler.

# Set default passmap to: foo/bar, spong/wibble
# set default handlerCmd to execCommand
proc telnetServer {port {passmap {foo bar spong wibble}} {handlerCmd execCommand}} {
    puts stdout "start*** telnetServer"
    if {$port == 0} {
        return -code error "Only non-zero port numbers are supported (L17)"
    }
    puts stdout "starting server $handlerCmd port $port"
    set server [socket -server [list connect $port $handlerCmd] $port]
    global passwords services hostname
    foreach {id pass} $passmap {set passwords($port,$id) $pass}
    set services($server) $handlerCmd
    puts "id/pass ${id} ${pass}"
    set hostname [info hostname]
    puts stdout "end***** telnetServer"
    return $server
}

## Removes the server on the given port, cleaning up the extra state too.
proc closedownServer {server} {
    global services passwords connections auth
    puts stdout "start*** closedownServer"
    set port [lindex [fconfigure $server -sockname] 2]
    catch {close $server}
    unset services($server)
    foreach passmap [array names passwords $port,*] {
        unset passwords($passmap)
    }
    # Hmph!  Have to remove unauthorized connections too, though any
    # connection which has been authorized can continue safely.
    foreach {client data} [array get connections] {
        if {$port == [lindex $data 0] && !$auth($client)} {
            disconnect $client
        }
    }
    puts stdout "end***** closedownServer"
}

## Handle an incoming connection to the given server
proc connect {serverport handlerCmd client clienthost clientport} {
    puts stdout "start*** connect"
    global auth cmd denyHosts connections hostname username
    if {[info exist denyHosts($clienthost)]} {
        puts stdout "${clienthost}:${clientport} attempted connection"
        catch {puts $client "Connection denied"}
        catch {close $client}
	puts stdout "end***** connect via L57"
        return
    }
    puts stdout "${clienthost}:${clientport} connected on $client"
    fileevent $client readable "handle $serverport $client"
    set auth($client) 0
    puts stdout "cmd($client) $handlerCmd"
    set cmd($client) $handlerCmd
    set connections($client) [list $serverport $clienthost $clientport]
    fconfigure $client -buffering none
    puts stdout "end***** connect"
}

## Disconnect the given client, cleaning up any connection-specific data
proc disconnect {client} {
    puts stdout "start*** disconnect"
    catch {close $client}
    global auth cmd connections
    unset auth($client)
    unset cmd($client)
    unset connections($client)
    puts stdout "$client disconnected"
    puts stdout "end***** disconnect"
}

## Handle data sent from the client.  Log-in is handled directly by this
## procedure, and requires the name and password on the same line
proc handle {serverport client} {
    global passwords auth cmd username
    puts stdout "start*** handle serverport '${serverport}' client '${client}'"
    if { ![info exists username($client)] } {
	catch {puts -nonewline $client "${hostname} login: "}
    } else {
	catch {puts -nonewline $client "Password: "}
    }
    
    if {[gets $client line] < 0} {
        disconnect $client
	puts stdout "end***** handle via L87"
        return
    }
    if {[string equal $line "quit"] || [string equal $line "exit"]} {
        disconnect $client
	puts stdout "end***** handle via L92"
        return
    }
    if {$auth($client)} {
	# If logged in, interpret input as follows:
        eval $cmd($client) [list $client $line 0]
        eval $cmd($client) [list $client $line 1]
	puts stdout "end***** handle via L100"
        return
    }

    # Following splits $line into id and pass vars
    foreach {id pass} [split $line] {break}
    
    if {![info exist pass]} {
	# this case appears to be triggered if there is no password
	# supplied for a user account. Yet I have not been able to trigger it..
	# It triggers now.. I've changed the logic.. but
	# It needs to switch between username/password also..
	#### Add username/password prompt paradigm here
        catch {puts -nonewline $client "Login (handle): "}
	puts stdout "end***** handle via L104"
        return
    }

    #### authentication logic
    if {
        [info exist passwords($serverport,$id)] &&
        [string equal $passwords($serverport,$id) $pass]
    } then {
        set auth($client) 1
        puts stdout "$id logged in on $client"
        catch {puts $client "Welcome, $id!"}
        eval $cmd($client) [list $client $line 1]
	puts stdout "end***** handle via L115"
        return
    }
    if {
        $pass eq "" && [info exist username($client)]
    } then {
	# get password
	puts stdout "ask for password"
	catch {puts -nonewline $client "Password: "}
    }
    if { ![info exist username($client)] } then {
	set username($serverport) $id
    } else {
	puts stdout "AUTH FAILURE ON $client"
	catch {puts $client "Unknown name or password"}
	disconnect $client
	puts stdout "end***** handle"
    }
}

## Standard handler for logged-in conversations and prompt-generation.
proc execCommand {client line prompt} {
    puts stdout "start*** execCommand client '${client}' line '${line}' prompt '${prompt}'"

    global tcl_platform hostname username
    if {$prompt ==  1} {
        catch {puts -nonewline $client "\$ "}
	puts stdout "end***** execCommand via L130"
        return
    }
    switch $tcl_platform(platform) {
        unix {
	    catch {exec sh -c $line <@$client >@$client 2>@$client}
        }
        default {
            catch {exec $line} data
            puts $client $data
        }
    }
    puts stdout "end***** execCommand"
}

telnetServer 12345 ;# DEFAULT NAMES/PASSWORDS
telnetServer 12346 {aleph alpha beth beta}

## Administration service handler.  Chains to the normal handler for
## everything it doesn't recognise itself.
proc admin {client line prompt} {
    puts stdout "start*** admin"
    if {$prompt == 1} {
        catch {puts -nonewline $client "# "}
	puts stdout "end***** admin via 154"
        return
    }
    set cmd [split $line]
    global denyHosts connections services
    if {[string equal $line "shutdown"]} {
        set ::termination 1
        puts stdout "Shutdown requested on $client"
        catch {puts $client "System will shut down as soon as possible"}
	puts stdout "end***** admin via 163"
        return -code return "SHUTTING DOWN"
	
    } elseif {[string equal [lindex $cmd 0] "deny"]} {
        set denyHosts([lindex $cmd 1]) 1
    } elseif {[string equal [lindex $cmd 0] "allow"]} {
        catch {unset denyHosts([lindex $cmd 1])}
    } elseif {[string equal $line "denied"]} {
        foreach host [array names denyHosts] {
            catch {puts $client $host}
        }
    } elseif {[string equal $line "connections"]} {
        set len 0
        foreach conn [array names connections] {
            if {$len < [string length $conn]} {
                set len [string length $conn]
            }
        }
        foreach {conn details} [array get connections] {
            catch {puts $client [format "%-*s = %s" $len $conn $details]}
        }
    } elseif {[string equal [lindex $cmd 0] "close"]} {
        set sock [lindex $cmd 1]
        if {[info exist connections($sock)]} {
            disconnect $sock
        }
    } elseif {[string equal $line "services"]} {
        set len 0
        foreach serv [array names services] {
            if {$len < [string length $serv]} {
                set len [string length $serv]
            }
        }
        foreach {serv handler} [array get services] {
            set port [lindex [fconfigure $serv -sockname] 2]
            catch {puts $client [format "%-*s (port %d) = handler %s" $len $serv $port $handler]}
        }
    } elseif {[string equal [lindex $cmd 0] "addService"]} {
        set service [eval telnetServer [lrange $cmd 1 end]]
        catch {puts $client "Created service as $service"}
    } elseif {[string equal [lindex $cmd 0] "removeService"]} {
        set service [lindex $cmd 1]
        if {[info exist services($service)]} {
            closedownServer $service
        }
    } else {
        # CHAIN TO DEFAULT
        execCommand $client $line 0
    }
    puts stdout "end***** admin"
}
telnetServer 12347 {root OfAllEvil} admin

puts stdout "Ready for service"

vwait termination
exit
