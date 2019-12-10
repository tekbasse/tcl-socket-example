# From: https://wiki.tcl-lang.org/page/terminal%3Apassword%3Aget
# DKF: Here's the cheap-and-cheerful version using stty tricks. :^)
# It does a bit less, but uses far less code. Unix only.
#

proc terminal:password:get {promptString} {

     # Turn off echoing, but leave newlines on.  That looks better.
     # Note that the terminal is left in cooked mode, so people can still use backspace
     exec stty -echo echonl <@stdin

     # Print the prompt
     puts -nonewline stdout $promptString
     flush stdout

     # Read that password!  :^)
     gets stdin password

     # Reset the terminal
     exec stty echo -echonl <@stdin

     return $password
}

