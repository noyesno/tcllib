# nntp.tcl --
#
#       nntp implementation for Tcl.
#
# Copyright (c) 1998-2000 by Ajuba Solutions.
# All rights reserved.
# 
# RCS: @(#) $Id: nntp.tcl,v 1.1 2000/06/16 20:54:24 kuchler Exp $

package provide nntp 0.1

namespace eval ::nntp {
    # The socks variable holds the handle to the server connections
    variable socks

    # The counter is used to help create unique connection names
    variable counter 0

    # commands is the list of subcommands recognized by nntp
    variable commands [list \
            "article"     \
            "authinfo"    \
            "body"        \
            "date"        \
            "group"       \
            "head"        \
            "help"        \
            "last"        \
            "list"        \
            "listgroup"   \
            "mode_reader" \
            "newgroups"   \
            "newnews"     \
            "next"        \
            "post"        \
            "stat"        \
            "quit"        \
            "xgtitle"     \
            "xhdr"        \
            "xover"       \
            "xpat"        \
            ]

    set ::nntp::eol "\n"

    # only export one command, the one used to instantiate a new
    # nntp connection 
    namespace export nntp

}

# ::nntp::nntp --
#
#       Create a new nntp connection.
#
# Arguments:
#        server -   The name of the nntp server to connect to (optional).
#        port -     The port number to connect to (optional).
#        name -     The name of the nntp connection to create (optional).
#
# Results:
#    Creates a connection to the a nntp server.  By default the
#    connection is established with the machine 'news' at port '119'
#    These defaults can be overridden with the environment variables
#    NNTPPORT and NNTPHOST, or can be passed as optional arguments

proc ::nntp::nntp {{server ""} {port ""} {name ""}} {
    global env
    variable connections
    variable counter
    variable socks

    # If a name wasn't specified for the connection, create a new 'unique'
    # name for the connection 

    if { [llength [info level 0]] < 4 } {
        set counter 0
        set name "nntp${counter}"
        while {[lsearch -exact [info commands] $name] >= 0} {
            incr counter
            set name "nntp${counter}"
        }
    }

    if { ![string equal [info commands ::$name] ""] } {
        error "command \"$name\" already exists, unable to create stack"
    }
    set socks($name) [list ]

    # Initialize instance specific variables

    set ::nntp::${name}data(debug) 0
    set ::nntp::${name}data(eol) "\n"

    # Logic to determine whether to use the specified nntp server, or to use
    # the default

    if {$server == ""} {
        if {[info exists env(NNTPSERVER)]} {
            set ::nntp::${name}data(host) "$env(NNTPSERVER)"
        } else {
            set ::nntp::${name}data(host) "news"
        }
    } else {
        set ::nntp::${name}data(host) $server
    }

    # Logic to determine whether to use the specified nntp port, or to use the
    # default.

    if {$port == ""} {
        if {[info exists env(NNTPPORT)]} {
            set ::nntp::${name}data(port) $env(NNTPPORT)
        } else {    
            set ::nntp::${name}data(port) 119
        }
    } else {
        set ::nntp::${name}data(port) $port
    }
 
    set ::nntp::${name}data(code) 0
    set ::nntp::${name}data(mesg) ""
    set ::nntp::${name}data(addr) ""

    #set sock [socket nntp.best.com 119]
    set sock [socket [set ::nntp::${name}data(host)] \
            [set ::nntp::${name}data(port)]]

    set ::nntp::${name}data(sock) $sock

    # Create the command to manipulate the nntp connection

    interp alias {} ::$name {} ::nntp::NntpProc $name
    
    ::nntp::response $name

    return $name
}

# ::nntp::NntpProc --
#
#       Command that processes all nntp object commands.
#
# Arguments:
#       name    name of the nntp object to manipulate.
#       args    command name and args for the command.
#
# Results:
#       Calls the appropriate nntp procedure for the command specified in
#       'args' and passes 'args' to the command/procedure.

proc ::nntp::NntpProc {name {cmd ""} args} {

    # Do minimal args checks here

    if { [llength [info level 0]] < 3 } {
        error "wrong # args: should be \"$name option ?arg arg ...?\""
    }

    # Split the args into command and args components

    if { [llength [info commands ::nntp::_$cmd]] == 0 } {
        variable commands
        set optlist [join $commands ", "]
        set optlist [linsert $optlist "end-1" "or"]
        error "bad option \"$cmd\": must be $optlist"
    }

    # Call the appropriate command with its arguments

    return [eval [list ::nntp::_$cmd $name] $args]
}

#proc ::nntp::EOL {name {eol ""}} {
#    if {"$eol" != ""} {
#        set ::nntp::${name}data(eol) $eol
#    }
#    return [set ::nntp::${name}data(eol)]
#}

#proc ::nntp::OK {name} {
#
#     # Codes less than 400 are good
#
#    return [expr {(0 < [set ::nntp::${name}data(code)]) && \
#            ([set ::nntp::${name}data(code)] < 400)}]
#}

# ::nntp::okprint --
#
#       Used to test the return code stored in data(code) to
#       make sure that it is alright to right to the socket.
#
# Arguments:
#       name    name of the nntp object.
#
# Results:
#       Either throws an error describing the failure, or
#       'args' and passes 'args' to the command/procedure or
#       returns 1 for 'OK' and 0 for error states.   

proc ::nntp::okprint {name} {

    if {([set ::nntp::${name}data(code)] >=400)} {
        set val [expr {(0 < [set ::nntp::${name}data(code)]) && \
                ([set ::nntp::${name}data(code)] < 400)}]
        error "NNTPERROR: [set ::nntp::${name}data(code)] \
                [set ::nntp::${name}data(mesg)]"
    }

    # Codes less than 400 are good

    return [expr {(0 < [set ::nntp::${name}data(code)]) \
            && ([set ::nntp::${name}data(code)] < 400)}]
}

# ::nntp::message --
#
#       Used to format data(mesg) for printing to the socket
#       by appending the appropriate end of line character which
#       is stored in data(eol).
#
# Arguments:
#       name    name of the nntp object.
#
# Results:
#       Returns a string containing the message from data(mesg) followed
#       by the eol character(s) stored in data(eol)

proc ::nntp::message {name} {
    return "[set ::nntp::${name}data(mesg)][set ::nntp::${name}data(eol)]"
}

# ::nntp::code --
#
#       Used to return the return codes value
#
# Arguments:
#       name    name of the nntp object.
#
# Results:
#       Returns the code stored in data(code)

#proc ::nntp::code {name} {
#    return [set ::nntp::${name}data(code)]
#}

# ::nntp::postok --
#
#       Used to determine when it is 'ok' to post
#
# Arguments:
#       name    name of the nntp object.
#
# Results:
#       Returns the code stored in data(post)

#proc ::nntp::postok {name} {
#    return [set ::nntp::${name}data(post)]
#}

#################################################
#
# NNTP Methods
#

# ::nntp::_article --
#
#       Internal article proc.  Called by the 'nntpName article' command.
#       Retrieves the article specified by msgid, in the group specified by
#       the 'nntpName group' command.  If no msgid is specified the current 
#       (or first) article in the group is retrieved
#
# Arguments:
#       name    name of the nntp object.
#       msgid   The article number to retrieve
#
# Results:
#       Returns the message (if there is one) from the specified group as
#       a valid tcl list where each element is a line of the message.
#       If no article is found, the "" string is returned.
#
# According to RFC 977 the responses are:
#
#   220 n  article retrieved - head and body follow
#           (n = article number,  = message-id)
#   221 n  article retrieved - head follows
#   222 n  article retrieved - body follows
#   223 n  article retrieved - request text separately
#   412 no newsgroup has been selected
#   420 no current article has been selected
#   423 no such article number in this group
#   430 no such article found
#
 
proc ::nntp::_article {name {msgid ""}} {
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "ARTICLE $msgid"]
}

# ::nntp::_authinfo --
#
#       Internal authinfo proc.  Called by the 'nntpName authinfo' command.
#       Passes the username and password for a nntp server to the nntp server. 
#
# Arguments:
#       name    Name of the nntp object.
#       user    The username for the nntp server.
#       pass    The password for 'username' on the nntp server.
#
# Results:
#       Returns the result of the attempts to set the username and password
#       on the nntp server ( 1 if successful, 0 if failed).

proc ::nntp::_authinfo {name {user "guest"} {pass "foobar"}} {
    set ::nntp::${name}data(cmnd) ""
    set res [::nntp::command $name "AUTHINFO USER $user"]
    if {$res} {
        set res [expr {$res && [::nntp::command $name "AUTHINFO PASS $pass"]}]
    }
    return $res
}

# ::nntp::_body --
#
#       Internal body proc.  Called by the 'nntpName body' command.
#       Retrieves the body of the article specified by msgid from the group
#       specified by the 'nntpName group' command. If no msgid is specified
#       the current (or first) message body is returned  
#
# Arguments:
#       name    Name of the nntp object.
#       msgid   The number of the body of the article to retrieve
#
# Results:
#       Returns the body of article 'msgid' from the group specified through
#       'nntpName group'. If msgid is not specified or is "" then the body of
#       the current (or the first) article in the newsgroup will be returned 
#       as a valid tcl list.  The "" string will be returned if there is no
#       article 'msgid' or if no group has been specified.

proc ::nntp::_body {name {msgid ""}} {
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "BODY $msgid"]
}

# ::nntp::_group --
#
#       Internal group proc.  Called by the 'nntpName group' command.
#       Sets the current group on the nntp server to the group passed in.
#
# Arguments:
#       name    Name of the nntp object.
#       group   The name of the group to set as the default group.
#
# Results:
#    Sets the default group to the group specified. If no group is specified
#    or if an invalid group is specified an error is thrown.
#
# According to RFC 977 the responses are:
#
#  211 n f l s group selected
#           (n = estimated number of articles in group,
#           f = first article number in the group,
#           l = last article number in the group,
#           s = name of the group.)
#  411 no such news group

proc ::nntp::_group {name {group ""}} {
    set ::nntp::${name}data(cmnd) "groupinfo"
    if {$group == ""} {
        set group [set ::nntp::${name}data(group)]
    }
    return [::nntp::command $name "GROUP $group"]
}

# ::nntp::_head --
#
#       Internal head proc.  Called by the 'nntpName head' command.
#       Retrieves the header of the article specified by msgid from the group
#       specified by the 'nntpName group' command. If no msgid is specified
#       the current (or first) message header is returned  
#
# Arguments:
#       name    Name of the nntp object.
#       msgid   The number of the header of the article to retrieve
#
# Results:
#       Returns the header of article 'msgid' from the group specified through
#       'nntpName group'. If msgid is not specified or is "" then the header of
#       the current (or the first) article in the newsgroup will be returned 
#       as a valid tcl list.  The "" string will be returned if there is no
#       article 'msgid' or if no group has been specified.

proc ::nntp::_head {name {msgid ""}} {
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "HEAD $msgid"]
}

# ::nntp::_help --
#
#       Internal help proc.  Called by the 'nntpName help' command.
#       Retrieves a list of the valid nntp commands accepted by the server.
#
# Arguments:
#       name    Name of the nntp object.
#
# Results:
#       Returns the NNTP commands expected by the NNTP server.

proc ::nntp::_help {name} {
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "HELP"]
}

proc ::nntp::_ihave {name {msgid ""}} {
    set ::nntp::${name}data(cmnd) "fetch"
    if {![::nntp::command $name "IHAVE $msgid"]} {
        return
    }
    return [::nntp::squirt $name "$args"]    
}

# ::nntp::_last --
#
#       Internal last proc.  Called by the 'nntpName last' command.
#       Sets the current message to the message before the current message.
#
# Arguments:
#       name    Name of the nntp object.
#
# Results:
#       None.

proc ::nntp::_last {name} {
    set ::nntp::${name}data(cmnd) "msgid"
    return [::nntp::command $name "LAST"]
}

# ::nntp::_list --
#
#       Internal list proc.  Called by the 'nntpName list' command.
#       Lists all groups or (optionally) all groups of a specified type.
#
# Arguments:
#       name    Name of the nntp object.
#       Type    The type of groups to return (active active.times newsgroups
#               distributions distrib.pats moderators overview.fmt
#               subscriptions) - optional.
#
# Results:
#       Returns a tcl list of all groups or the groups that match 'type' if
#       a type is specified.

proc ::nntp::_list {name {type ""}} {
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "LIST $type"]
}

# ::nntp::_newgroups --
#
#       Internal newgroups proc.  Called by the 'nntpName newgroups' command.
#       Lists all new groups since a specified time.
#
# Arguments:
#       name    Name of the nntp object.
#       since   The time to find new groups since.  The time can be in any
#               format that is accepted by 'clock scan' in tcl.
#
# Results:
#       Returns a tcl list of all new groups added since the time specified. 

proc ::nntp::_newgroups {name since args} {
    set since [clock format [clock scan "$since"] -format "%y%m%d %H%M%S"]
    #set dist [distributions $name "$args"]
    set dist ""
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "NEWGROUPS $since $dist"]
}

# ::nntp::_newnews --
#
#       Internal newnews proc.  Called by the 'nntpName newnews' command.
#       Lists all new news in the specified group since a specified time.
#
# Arguments:
#       name    Name of the nntp object.
#       group   Name of the newsgroup to query.
#       since   The time to find new groups since.  The time can be in any
#               format that is accepted by 'clock scan' in tcl. Defaults to
#               "1 day ago"
#
# Results:
#       Returns a tcl list of all new messages since the time specified. 

proc ::nntp::_newnews {name {group ""} {since ""} {args ""}} {
    if {$group != ""} {
        if {[regexp {^[\w\.\-]+$} $group] == 0} {
        #if {[string is digit $group]} {}
            set since $group
            set group ""
        }
    }
    if {![info exists group] || ($group == "")} {
        if {[info exists ::nntp::${name}data(group)] \
                && ([set ::nntp::${name}data(group)] != "")} {
            set group [set ::nntp::${name}data(group)]
        } else {
            set group "*"
        }
    }
    if {"$since" == ""} {
        set since [clock format [clock scan "now - 1 day"]]
    }
    set since [clock format [clock scan $since] -format "%y%m%d %H%M%S"]
    #set dist [nntp::_list $name distributions]
    set dist "" 
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "NEWNEWS $group $since $dist"]
}

# ::nntp::_next --
#
#       Internal next proc.  Called by the 'nntpName next' command.
#       Sets the current message to the next message after the current message.
#
# Arguments:
#       name    Name of the nntp object.
#
# Results:
#       None.

proc ::nntp::_next {name} {
    set ::nntp::${name}data(cmnd) "msgid"
    return [::nntp::command $name "NEXT"]
}

# ::nntp::_post --
#
#       Internal post proc.  Called by the 'nntpName post' command.
#       Posts a message to a newsgroup.
#
# Responses (according to RFC 977) to a post request:
#  240 article posted ok
#  340 send article to be posted. End with .
#  440 posting not allowed
#  441 posting failed
#
# Arguments:
#       name    Name of the nntp object.
#       args    A message of the form specified in RFC 850
#
# Results:
#       None.

proc ::nntp::_post {name args} {
    
    if {![::nntp::command $name "POST"]} {
        return
    }
    return [::nntp::squirt $name "$args"]
}

# ::nntp::_slave --
#
#       Internal slave proc.  Called by the 'nntpName slave' command.
#       Identifies a connection as being made from a slave nntp server.
#       This might be used to indicate that the connection is serving
#       multiple people and should be given priority.  Actual use is 
#       entirely implementation dependant and may vary from server to
#       server.
#
# Arguments:
#       name    Name of the nntp object.
#
# Results:
#       None.
#
# According to RFC 977 the only response is:
#
#    202 slave status noted

proc ::nntp::_slave {name} {
    return [::nntp::command $name "SLAVE"]
}

# ::nntp::_stat --
#
#       Internal stat proc.  Called by the 'nntpName stat' command.
#       The stat command is similar to the article command except that no
#       text is returned.  When selecting by message number within a group,
#       the stat command serves to set the current article pointer without
#       sending text. The returned acknowledgement response will contain the
#       message-id, which may be of some value.  Using the stat command to
#       select by message-id is valid but of questionable value, since a
#       selection by message-id does NOT alter the "current article pointer"
#
# Arguments:
#       name    Name of the nntp object.
#       msgid   The number of the message to stat (optional) default is to
#               stat the current article
#
# Results:
#       Returns the statistics for the article.

proc ::nntp::_stat {name {msgid ""}} {
    set ::nntp::${name}data(cmnd) "status"
    return [::nntp::command $name "STAT $msgid"]
}

# ::nntp::_quit --
#
#       Internal quit proc.  Called by the 'nntpName quit' command.
#       Quits the nntp session and closes the socket.  Deletes the command
#       that was created for the connection.
#
# Arguments:
#       name    Name of the nntp object.
#
# Results:
#       Returns the return value from the quit command.

proc ::nntp::_quit {name} {

    set ret [::nntp::command $name "QUIT"]
    close [set ::nntp::${name}data(sock)]
    rename ${name} {}
    return $ret
}

#############################################################
#
# Extended methods (not available on all NNTP servers
#

proc ::nntp::_date {name} {
    set ::nntp::${name}data(cmnd) "msg"
    return [::nntp::command $name "DATE"]
}

proc ::nntp::_listgroup {name {group ""}} {
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "LISTGROUP $group"]
}

proc ::nntp::_mode_reader {name} {
    set ::nntp::${name}data(cmnd) "msg"
    return [::nntp::command $name "MODE READER"]
}

proc ::nntp::_xgtitle {name {group_pattern ""}} {
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "XGTITLE $group_pattern"]
}

proc ::nntp::_xhdr {name {header "message-id"} {list ""} {last ""}} {
    if {![regexp {\d+-\d+} $list]} {
        if {"$last" != ""} {
            set list "$list-$last"
        } else {
            set list ""
	}
    }
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "XHDR $header $list"]    
}

proc ::nntp::_xindex {name {group ""}} {
    if {("$group" == "") && [info exists ::nntp::${name}data(group)]} {
        set group [set ::nntp::${name}data(group)]
    }
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "XINDEX $group"]    
}

proc ::nntp::_xmotd {name {since ""}} {
    if {"$since" != ""} {
        set since [clock seconds]
    }
    set since [clock format [clock scan $since] "%y%m%d %H%M%S"]
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "XMOTD $since"]    
}

proc ::nntp::_xover {name {list ""} {last ""}} {
    if {![regexp {\d+-\d+} $list]} {
        if {"$last" != ""} {
            set list "$list-$last"
        } else {
            set list ""
	}
    }
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "XOVER $list"]
}

# TODO

proc ::nntp::_xpat {name {header "subject"} {list 1} {last ""} {args ""}} {
    set patterns ""

    if {![regexp {\d+-\d+} $list]} {
        if {("$last" != "") && ([string is digit $last])} {
            set list "$list-$last"
        }
    } elseif {"$last" != ""} {
        set patterns "$last"
    }
    
    if {"$args" != ""} {
        set patterns "$patterns $args"
    }

    if {"$patterns" == ""} {
        set patterns "*"
    }
    
    set ::nntp::${name}data(cmnd) "fetch"
    return [::nntp::command $name "XPAT $header $list $patterns"]
}

proc ::nntp::_xpath {name {msgid ""}} {
    set ::nntp::${name}data(cmnd) "msg"
    return [::nntp::command $name "XPATH $msgid"]
}

proc ::nntp::_xsearch {name} {
    set res [::nntp::commmand $name "XSEARCH"]
    if {!$res} {
        return
    }
    #squirt
}

proc ::nntp::_xthread {name {args ""}} {
    if {"$args" != ""} {
        set filename "dbinit"
    } else {
        set filename "thread"
    }
    set ::nntp::${name}data(cmnd) "fetchbinary"
    return [::nntp::command $name "XTHREAD $filename"]
}

######################################################
#
# Helper methods
#

proc ::nntp::cmd {name cmd} {
    set eol "\015\012"
    set sock [set ::nntp::${name}data(sock)]
    if {[set ::nntp::${name}data(debug)]} {
        puts stderr "$sock command $cmd"
    }
    puts $sock "$cmd"
    flush $sock
    return
}

proc ::nntp::command {name args} {
    set res [eval [list ::nntp::cmd $name] $args]
    
    return [::nntp::response $name]
}

proc ::nntp::msg {name} {
    set res [::nntp::okprint $name]
    if {!$res} {
        return
    }
    return [set ::nntp::${name}data(mesg)]
}

proc ::nntp::groupinfo {name} {
    set ::nntp::${name}data(group) ""

    if {[::nntp::okprint $name] && [regexp {(\d+)\s+(\d+)\s+(\d+)\s+([\w\.]+)} \
            [set ::nntp::${name}data(mesg)] match count first last \
            ::nntp::${name}data(group)]} {
        return [list $count $first $last [set ::nntp::${name}data(group)]]
    }
}

proc ::nntp::msgid {name} {
    set result ""
    if {[::nntp::okprint $name] && [regsub {\s+<[^>]+>} [set ::nntp::${name}data(mesg)] {} result]} {
        return $result
    } else {
        return ""
    }
}

proc ::nntp::status {name} {
    set result ""
    if {[::nntp::okprint $name] && [regexp {\d+\s+<[^>]+>} [set ::nntp::${name}data(mesg)] result]} {
        return $result
    } else {
        return ""
    }
}

proc ::nntp::fetch {name} {
    set eol "\012"

    if {![::nntp::okprint $name]} {
        return
    }
    set sock [set ::nntp::${name}data(sock)]

    set result [list ]
    while {![eof $sock]} {
        gets $sock line
        regsub {\015?\012$} $line [set ::nntp::${name}data(eol)] line

        if {[regexp {^\.$} $line]} {
            break
        }
        regsub {^\.\.} $line {.} line
        lappend result $line
    }
    return $result
}

proc ::nntp::response {name} {
    set eol "\012"

    set sock [set ::nntp::${name}data(sock)]

    gets $sock line
    set ::nntp::${name}data(code) 0
    set ::nntp::${name}data(mesg) ""

    if {$line == ""} {
        error "nntp: unexpected EOF on $sock\n"
    }

    regsub {\015?\012$} $line "" line

    set result [regexp {^((\d\d)(\d))\s*(.*)} $line match \
        ::nntp::${name}data(code) val1 val2 ::nntp::${name}data(mesg)]
    
    if {$result == 0} {
        puts stderr "nntp garpled response: $line\n";
        return
    }

    if {$val1 == 20} {
        set ::nntp::${name}data(post) [expr {!$val2}]
    }

    if {[set ::nntp::${name}data(debug)]} {
        puts stderr "val1 $val1 val2 $val2"
        puts stderr "code '[set ::nntp::${name}data(code)]'"
        puts stderr "mesg '[set ::nntp::${name}data(mesg)]'"
        if {[info exists ::nntp::${name}data(post)]} {
            puts stderr "post '[set ::nntp::${name}data(post)]'"
        }
    } 

    return [::nntp::returnval $name]
}

proc ::nntp::returnval {name} {
    if {([info exists ::nntp::${name}data(cmnd)]) \
            && ([set ::nntp::${name}data(cmnd)] != "")} {
        set command [set ::nntp::${name}data(cmnd) ]
    } else {
        set command okprint
    }
    
    if {[set ::nntp::${name}data(debug)]} {
        puts stderr "returnval command '$command'"
    }

    set ::nntp::${name}data(cmnd) ""
    return [::nntp::$command $name]
}

#eof

