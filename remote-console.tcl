#!/usr/bin/env tclsh

# helper procs from elsewhere:

# From: https://wiki.tcl-lang.org/page/terminal%3Apassword%3Aget
# GPS - Thu May 9, 2002: I use the following code in my file server
# to receive a password. It is quite nice, because
# it displays * for each entered character.
# It supports backspace, and
# when a control key is pressed it's ignored, instead of appending
# to the string.
# It uses the Unix Terminal Extension which is in the public domain.
# I place this code in the public domain too.
# Please feel free to extend this.
proc terminal:password:get {str} {
    terminal:canonicalOff
    terminal:echoOff

    puts -nonewline $str
    flush stdout
  
    set chr ""
    set inputStr ""
    while 1 {
      set chr [read stdin 1]
      #Backspace
      if {$chr == "\b"} {
        if {[string length $inputStr] > 0} {
          puts -nonewline "\x1b\[D"
          puts -nonewline " "
          puts -nonewline "\x1b\[1D"
          set lastChar [expr {[string length $inputStr] - 2}]
          set inputStr [string range $inputStr 0 $lastChar]
          flush stdout
        }
        continue
      }
  
      #eat up escape characters
      #example: ESCc ESC\[D ESC\[1D ESC\[11D
      if {$chr == "\x1b"} {
        set nextChar [read stdin 1]
        if {$nextChar == "\["} {
          #This isn't a simple 2 char escape sequence
          #It could be ESC\[D or ESC\[= or ESC\[1D
          set nextChar [read stdin 1]
          if {[string is digit $nextChar] || $nextChar == "="} {
            while 1 {
              #eat up the digits
              set nextChar [read stdin 1]
              if {[string is digit $nextChar]} {
                continue
              } else {
                #We read a char that wasn't a digit, so we are at the end.
                #If the string we had was ESC\[22D we just read D
                break
              }
            }
          }
        }
        continue
      }
  
      if {$chr == "\n" || $chr == "\r"} {
        break
      }
      append inputStr $chr
      puts -nonewline *
      flush stdout
    }
    terminal:canonicalOn
    terminal:echoOn
  
    #DEBUG
    puts "\n$inputStr"
  
    if {[string length $inputStr] <= 0} {
      return -code error "Please specify one or more characters for your password.\n"
    }
  
    return $inputStr
}



# Read a single line of input from the terminal without echoing to the
# screen.  If Control-C is pressed, exit immediately.
#
proc tty_gets_no_echo {{prompt {}} {channel_in {stdin}} {channel_out {stdout}}} {
    if {$prompt!=""} {
	puts -nonewline $prompt
    }
    flush $channel_out
    global _tty_input _tty_wait tcl_platform
    if {$tcl_platform(platform)!="unix"} {
	# FIXME:  This routine only works on unix.  On other platforms, the
	# password is still echoed to the screen as it is typed.
	if { [gets $channel_in i] < 0 } {
	    disconnect $channel_in
	    puts "end***** tty_gets_no_echo via L19"
	}
	return $i
    }
    set _tty_input {}
    set _tty_wait 0
    fileevent $channel_in readable _tty_read_one_character $channel_in
    exec /bin/stty raw -echo <@$channel_in
    vwait ::_tty_wait
    fileevent $channel_in readable {}
    return $_tty_input
}

proc _tty_read_one_character {channel_in} {
    set c [read $channel_in 1]
    if {$c=="\n" || $c=="\003"} {
	exec /bin/stty -raw echo <@$channel_in
	puts ""
	if {$c=="\003"} exit
	incr ::_tty_wait
    } else {
	append ::_tty_input $c
    }
}






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
# Ben adding:
# hostname: hostname for telnet emulation
# username(client): username provided for authentication
# auth_input_count(client): count of login attempts

proc telnetServer {port {passmap {cats Buyo kagome Kagome}} {handlerCmd execCommand}} {
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
    global auth cmd denyHosts connections
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
    global passwords auth cmd hostname username auth_input_count
    set tries_max 5
    puts stdout "start*** handle serverport '${serverport}' client '${client}'"
    while { 1 } {
	# User needs to send a return to flush/synchronize the buffer
	if { ![info exist auth_input_count($client)] } {
	    set auth_input_count($client) 0
	}
	if { $auth_input_count($client) == 0 } {
	    if {[gets $client line] < 0} {
		disconnect $client
		puts stdout "end***** handle via L87"
		return
	    }
	} else {
	    if {[gets $client line] < 0} {
		disconnect $client
		puts stdout "end***** handle via L239"
		return
	    }
	}

	# Puts appropriate prompt
	if {$auth($client)} {
	    # If logged in, interpret input as follows:
	    eval $cmd($client) [list $client $line 0]
	    eval $cmd($client) [list $client $line 1]
	    puts stdout "end***** handle via L100"
	    return
	} else {
	    set prompt_username_p 1
	    puts stdout "prompt_username_p $prompt_username_p"
	    if { ![info exists username($client)] } {
		#catch {puts -nonewline $client "${hostname} login: "}
		puts -nonewline $client "${hostname} login: "
	    } else {
		set prompt_username_p 0
		set prompt "Password: "
		#catch {puts -nonewline $client $prompt}
		puts -nonewline $client "Password(116): "
		
	    }
	    puts stdout "prompt_username_p $prompt_username_p"
	}

	if {$prompt_username_p != 0 } {
	    if {[gets $client line] < 0} {
		disconnect $client
		puts stdout "end***** handle via L87"
		return
	    }
	} else {
	    # gets line via if gets client line
	}
	
	# Get input as 'line'
	puts stdout "line: '$line'"
	### uncommented following.
	if {[string equal $line "quit"] || [string equal $line "exit"]} {
	    disconnect $client
		puts stdout "end***** handle via L92"
	    return
	}

	# Following splits $line into id and pass vars
	#foreach {id pass} [split $line] {break}
	# Replaced with:
	if { $prompt_username_p } {
	    set username($client) $line
	    set id $line
	} else {
	    set id username($client)
	    set pass $line
	}
	
	if {![info exist pass]} {
	    # this case is triggered when there is no password
	    # supplied for a user account.

	    # Turn off key echo for password
	    #exec stty -echo echonl <@stdin
	    
	    #catch {puts -nonewline $client "Login (handle): "}
	    puts -nonewline $client "Password: "

	    if {[gets $client pass] < 0} {
		disconnect $client
	    }

	    # Turn on key echo
	    #exec stty echo -echonl <@stdin
	    
	    # Don't return until after authentication process
	    #puts stdout "end***** handle via L135"
	    #return
	    
	}


	# Authenticate
	set auth_input_count($client) [expr { $auth_input_count($client) + 1 } ]
	
	if {
	    [info exist passwords($serverport,$id)] &&
	    [string equal $passwords($serverport,$id) $pass]
	} then {
	    set auth($client) 1
	    puts stdout "$id logged in on $client"
	    catch {puts $client "Welcome, $id!"}
	    eval $cmd($client) [list $client $line 1]
	    puts stdout "end***** handle via L151"
	    return
	}
	if { ![info exist username($client)] } then {
	    puts stdout "end***** handle via L171"
	    set username($client) $id
	    # return
	} else {
	    puts stdout "AUTH FAILURE ON $client"
	    catch {puts $client "Login incorrect"}
	    unset username($client)
	    if { $auth_input_count($client) >= $tries_max } {
		puts $client "Maximum number of tries exceeded (${tries_max})"
		unset auth_input_count($client)
		disconnect $client
		puts stdout "end***** handle"
	    }
	}
	unset id
	unset pass
	puts stdout "end***** hanble via L181"
    }
}

## Standard handler for logged-in conversations and prompt-generation.
proc execCommand {client line prompt} {
    puts stdout "start*** execCommand client '${client}' line '${line}' prompt '${prompt}'"

    global tcl_platform hostname username
    if {$prompt ==  1} {
        #catch {puts -nonewline $client "\$ "}
	puts -nonewline $client "\$ "
	puts stdout "end***** execCommand via L130"
        return
    }
    switch $tcl_platform(platform) {
        unix {
	    #exec /bin/sh -c $line <@$client >@$client 2>@$client
	    catch {exec /bin/sh -c $line <@$client >@$client 2>@$client} {
		return
	    }
        }
        default {
            catch {exec $line} data
            puts $client $data
        }
    }
    puts stdout "end***** execCommand"
}

telnetServer 2038;# DEFAULT NAMES/PASSWORDS

puts stdout "Ready for service"

vwait termination
exit

