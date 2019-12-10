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
    #puts "\n$inputStr"
  
    if {[string length $inputStr] <= 0} {
      return -code error "Please specify one or more characters for your password.\n"
    }
  
    return $inputStr
}
DKF: Here's the cheap-and-cheerful version using stty tricks. :^) It does a bit less, but uses far less code. Unix only.

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

