lappend auto_path [file join [file dirname [info script]] ..] [file join [file dirname [info script]] .. win]

package require Tk
package require json
package require tdjson

wm withdraw .

option add *app*log*list*width      100 widgetDefault
option add *app*log*list*height      30 widgetDefault
option add *app*opt*list*width       50 widgetDefault
option add *app*opt*list*height      30 widgetDefault
option add *app*input*Entry*width    50 widgetDefault

namespace eval app {
    variable input ""
    variable widget
    array set widget {}
}    

proc app::init {} {
    CreateToplevel .app "explore tdjson" [namespace code quit]
    CreateListbox .app.log list
    pack [checkbutton [frame .app.logbtn].enable -text enabled -variable cfg::_app_log_enabled] \
            -padx 8 -anchor e
    CreateState .app.auth \
            "client id:" td::clientId \
            "authorization state:" td::authorizationState \
            "connection state:" td::connectionState
    CreateButtons .app.btn \
            createClient "create client" [namespace code createClient] \
            authAction "complete auth" [namespace code completeAuth] \
            showOptions "show options" [namespace code showOptions] \
            quit "quit" [namespace code quit]
    pack .app.log -fill both -expand true
    pack .app.logbtn -fill x
    pack .app.auth -fill x
    pack .app.btn -fill x
    set app::widget(log) .app.log
    set app::widget(auth) .app.auth
    set app::widget(btn) .app.btn

    CreateToplevel .app.opt "options" {wm withdraw .app.opt}
    CreateListbox .app.opt.opt list
    CreateButtons .app.opt.btn hide "close" {wm withdraw .app.opt}
    pack .app.opt.opt -fill both -expand true
    pack .app.opt.btn -fill x
    set app::widget(opt) .app.opt.opt

    wm deiconify .app
    update

    td::setLogCallback [namespace code UpdateLog]
    td::setOptionsCallback [namespace code UpdateOptions]
    td::receiveBgStart
}

proc app::quit {} {
    td::receiveBgStop
    exit
}

proc app::createClient {} {
    if {$td::clientId ne ""} {
        messageBox "warning" warning "client already created as #$td::clientId"
    } else {
        td::createClient
        send "create client" "getOption" "name" [jsonString "version"]
    }
}

proc app::send {title type args} {
    popup open $title "sending $type ..." "close"
    set extra [td::send $type {*}$args]
    while {[popup active]} {
        # popup grabs events, call receive directly
        td::receive $td::receiveBgTimeout
        set response [td::received $extra]
        if {$response ne ""} {
            popup update $title "response to $type\n[string range $response 0 256]" "Ok"
            break
        }
        update
    }
}

proc app::completeAuth {} {
    set title "complete auth"
    switch -- $td::authorizationState {
        "authorizationStateClosed" {
            tk_messageBox -parent .app -icon info -message "client is closed, create new client"
        }
        "authorizationStateWaitTdlibParameters" {
            if {[input $title "api id" cfg::api_id "api hash" cfg::api_hash]} {
                send $title "setTdlibParameters" \
                        "database_directory"   [jsonString $cfg::database_directory] \
                        "use_message_database"             $cfg::use_message_database \
                        "use_secret_chats"                 $cfg::use_secret_chats \
                        "api_id"                           $cfg::api_id \
                        "api_hash"             [jsonString $cfg::api_hash] \
                        "system_language_code" [jsonString $cfg::system_language_code] \
                        "device_model"         [jsonString $cfg::device_model] \
                        "application_version"  [jsonString $cfg::application_version] \
                        "enable_storage_optimizer"         $cfg::enable_storage_optimizer
            }
        }
        "authorizationStateWaitPhoneNumber" {
            if {[input $title "your phone number" cfg::phone_number]} {
                send $title "setAuthenticationPhoneNumber" \
                        "phone_number" [jsonString $cfg::phone_number]
            }
        }
        "authorizationStateWaitEmailAddress" {
            if {[input $title "your email address" cfg::email_address]} {
                send $title "setAuthenticationEmailAddress" \
                        "email_address" [jsonString $cfg::email_address]
            }
        }
        "authorizationStateWaitEmailCode" {
            if {[input $title "email authentication code you received" cfg::code]} {
                send $title "emailAddressAuthenticationCode" \
                        "code" [jsonString $cfg::code]
            }
        }
        "authorizationStateWaitCode" {
            if {[input $title "authentication code you received" cfg::code]} {
                send $title "checkAuthenticationCode" \
                        "code" [jsonString $cfg::code]
            }
        }
        "authorizationStateWaitRegistration" {
            if {[input $title "your first name" cfg::first_name "your last name" cfg::last_name]} {
                send $title "registerUser" \
                        "first_name" [jsonString $cfg::first_name] \
                        "last_name" [jsonString $cfg::last_name]
            }
        }
        "authorizationStateWaitPassword" {
            if {[input $title "your password" cfg::password]} {
                send $title "checkAuthenticationPassword" \
                        "password" [jsonString $cfg::password]
            }
        }
    }
}

proc app::showOptions {} {
    set w [winfo toplevel $app::widget(opt)]
    expr {[winfo ismapped $w] ? [wm withdraw $w] : [wm deiconify $w; raise $w]}
}

proc app::messageBox {title icon message} {
    tk_messageBox -parent .app -type ok -title $title -icon $icon -message $message
}

proc app::input {title args} {
    set w .app.input
    CreateToplevel $w $title {set app::input "cancel"}
    set i 0
    foreach {prompt varname} $args {
        grid [label $w.l$i -text $prompt -anchor e] [entry $w.e$i] -pady 4 -padx 4 -sticky we
        upvar $varname var$i
        if {[info exists var$i]} {
            $w.e$i insert 0 [set var$i]
        }
        incr i
    }
    CreateButtons $w.btn ok "ok" {set app::input "ok"} cancel "cancel" {set app::input "cancel"}
    grid $w.btn -columnspan 2 -sticky news
    grid rowconfig $w 0 -weight 1
    grid columnconfig $w 1 -weight 1
    tk::PlaceWindow $w widget .app
    wm transient $w .app
    tkwait visibility $w
    tk::SetFocusGrab $w $w.btn.ok
    vwait app::input
    if {$app::input eq "ok"} {
        set i 0
        foreach {- -} $args {
            set var$i [$w.e$i get]
            incr i
        }
    }
    tk::RestoreFocusGrab $w $w.btn.ok
    expr {$app::input eq "ok"}
}

proc app::popup {command args} {
    set w .app.popup
    switch -- $command {
        open {
            set cmd [namespace code [list app::popup close]]
            lassign $args title message button
            CreateToplevel $w $title $cmd
            pack [label $w.msg -text $message] -padx 8 -pady 8 -fill both -expand 1
            pack [button $w.btn -text $button -command $cmd] -fill x -expand 1
            tk::PlaceWindow $w widget .app
            wm transient $w .app
            tkwait visibility $w
            tk::SetFocusGrab $w $w.btn
        }
        active {
            return [winfo exists $w]
        }
        update {
            lassign $args title message button
            wm title $w $title
            $w.msg configure -text $message
            $w.btn configure -text $button
        }
        close {
            tk::RestoreFocusGrab $w $w.btn
        }
        default {
            error "invalid app::popup command '$command'"
        }
    }
}

proc app::UpdateLog {message} {
    if {$cfg::_app_log_enabled} {
        set end [$app::widget(log).list index end]
        if {$end >= $cfg::_app_log_max_lines} {
            $app::widget(log).list delete 0 [expr {$end - $cfg::_app_log_max_lines}]
        }
        $app::widget(log).list insert end $message
        $app::widget(log).list see end
    }
}

proc app::UpdateOptions {name value} {
    $app::widget(opt).list delete 0 end
    $app::widget(opt).list insert end \
        {*}[lmap n [dict keys $::td::options] {format "%s: %s" $n [dict get $::td::options $n]}]
}

proc app::CreateToplevel {w title delete} {
    toplevel $w
    wm withdraw $w
    wm title $w $title
    wm protocol $w WM_DELETE_WINDOW $delete
}

proc app::CreateListbox {w name} {
    frame $w
    listbox $w.$name \
            -xscrollcommand [list $w.sx set] \
            -yscrollcommand [list $w.sy set]
    scrollbar $w.sx -orient horizontal -command [list $w.$name xview]
    scrollbar $w.sy -orient vertical -command [list $w.$name yview]
    grid $w.$name -column 0 -row 0 -sticky news
    grid $w.sx -column 0 -row 1 -sticky we
    grid $w.sy -column 1 -row 0 -sticky ns
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 0 -weight 1
}

proc app::CreateState {w args} {
    frame $w
    set i 0
    foreach {label varname} $args {
        grid [label $w.l$i -text $label -anchor e] [label $w.s$i -textvariable $varname -anchor w] \
            -sticky we
        incr i
    }
}

proc app::CreateButtons {w args} {
    frame $w
    pack {*}[lmap {name text command} $args {button $w.$name -text $text -command $command}] \
        -fill x -side left -expand 1
}

namespace eval td {
    variable clientId ""
    variable authorizationState ""
    variable connectionState ""

    variable options [dict create]
    variable queries [dict create]

    variable logCallback ""
    variable optionsCallback ""
    variable receiveBgTimeout 0.01
}

proc td::init {} {
    td_set_log_message_callback 0 td::Fatal
    td_execute [jsonObject "@type" [jsonString "setLogVerbosityLevel"] "new_verbosity_level" 1]
}

proc td::execute {type args} {
    set json [jsonObject "@type" [jsonString $type] {*}$args]
    Log "EXEC>" $json
    Parse "EXEC<" [td_execute $json]
}

proc td::createClient {} {
    if {$td::clientId eq ""} {
        set td::clientId [td_create_client_id]
    }
}

proc td::send {type args} {
    if {$td::clientId ne ""} {
        set extra [clock clicks]
        set json [jsonObject "@type" [jsonString $type] "@extra" $extra {*}$args]
        Log "SEND>" $json
        td_send $td::clientId $json
        dict set td::queries $extra ""
        return $extra
    }
    return ""
}

proc td::receive {timeout} {
    Parse "RECV<" [td_receive $timeout]
}

proc td::received {extra} {
    if {[dict exists $td::queries $extra]} {
        set event [dict get $td::queries $extra]
        if {$event ne ""} {
            dict unset td::queries $extra
            return $event
        }
    }
    return ""
}

proc td::receiveBgStart {} {
    receive $td::receiveBgTimeout
    update
    after idle [namespace code receiveBgStart]
}

proc td::receiveBgStop {} {
    after cancel [namespace code receiveBgStart]
}

proc td::setLogCallback {callback} {
    set td::logCallback $callback
}

proc td::setOptionsCallback {callback} {
    set td::optionsCallback $callback
}

proc td::Parse {info json} {
    if {$json eq ""} return
    Log $info $json
    try {
        set event [json::json2dict $json]
    } on error message {
        Log "ERROR" $message
        return ""
    }
    if {[dict exists $event "@extra"]} {
        dict set td::queries [dict get $event "@extra"] $json
    }
    if {[dict exists $event "@type"]} {
        switch -- [dict get $event "@type"] {
            "updateOption" {
                if {[dict exists $event "name"] && [dict exists $event "value" "value"]} {
                    set n [dict get $event "name"]
                    set v [dict get $event "value" "value"]
                    if {![dict exists $td::options $n] || [dict get $td::options $n] ne $v} {
                        dict set td::options $n $v
                        if {$td::optionsCallback ne ""} {
                            uplevel #0 $td::optionsCallback $n $v
                        }
                    }
                }
            }
            "updateAuthorizationState" {
                if {[dict exists $event "authorization_state" "@type"]} {
                    set td::authorizationState [dict get $event "authorization_state" "@type"]
                }
            }
            "updateConnectionState" {
                if {[dict exists $event "state" "@type"]} {
                    set td::connectionState [dict get $event "state" "@type"]
                }
            }
        }
    }
    return $event
}

proc td::Log {info text} {
    # debug $info:$text
    if {$td::logCallback ne ""} {
        uplevel #0 $td::logCallback [list [format "%s %s" $info $text]]
    }
}

proc td::Fatal {level message} {
    debug "TDLib message: $level $message"
    if {$level == 0} {
        set td::clientId ""
        td::receiveBgStop
        tk_messageBox -title "TDLib fatal error" -icon error -message $message
        exit 1
    }
}

namespace eval cfg {
    variable _debug 0
    variable _app_log_max_lines 1000
    variable _app_log_enabled 1
    variable api_id ""
    variable api_hash ""
    variable database_directory "tdlib"
    variable use_message_database 1
    variable use_secret_chats 1
    variable system_language_code "en"
    variable device_model "Desktop"
    variable application_version "1.0"
    variable enable_storage_optimizer 1    
    variable phone_number ""
    variable email_address ""
    variable code ""
    variable first_name ""
    variable last_name ""
    variable password ""

    proc init {} {
        set n [expr {$::argc ? [lindex $::argv 0] : "[file rootname [info script]].cfg"}]
        if {$::argc || [file exists $n]} {
            try {
                set f [open $n "r"]
                foreach l [split [read $f] \n] {
                    set l [string trim $l]
                    if {$l ne "" && [string range $l 0 0] != "#"} {
                        variable {*}[lrange $l 0 end]
                    }
                }
            } on error message {
                tk_messageBox -title "config warning" -icon warning \
                        -message "error opening config file $n:\n$message"
            } finally {
                catch {close $f}
            }
        }
        if {$cfg::_debug} {
            if {[info commands console] ne ""} {
                console show
            } else {
                catch {
                    package require tkcon
                    tkcon show
                }
            }
        }
    }
}

proc jsonArray {args} {return \[[join $args ,]\]}
proc jsonString {str} {return [join [list \" [string map {\" \\\" \n \\n \r \\r \t \\t \\ \\\\} $str] \"] ""]}
proc jsonObject {args} {
    # args: ?name0 value0? ?name1 value1? ?jsonobject?
    set result {}
    if {[llength $args] % 2} {
        foreach {n v} [lrange $args 0 end-1] {
            lappend result [jsonString $n]:$v
        }
        set a [lindex $args end]
        if {$a ne ""} {
            lappend result $a
        }
    } else {
        foreach {n v} $args {
            lappend result [jsonString $n]:$v
        }
    }
    return \{[join $result ,]\}
}

proc debug {message} {
    if {$cfg::_debug} {
        puts stderr $message
    }
}

cfg::init
td::init
app::init
