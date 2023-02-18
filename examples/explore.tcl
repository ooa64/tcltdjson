lappend auto_path [file join [file dirname [info script]] ..] [file join [file dirname [info script]] .. win]

package require Tk
package require json
package require tdjson

wm withdraw .

foreach list {options users chats} {
    option add *app*$list*list*width 50 widgetDefault
    option add *app*$list*list*height 30 widgetDefault
    unset list
}
option add *app*log*list*width 100 widgetDefault
option add *app*log*list*height 30 widgetDefault
option add *app*input*Entry*width 50 widgetDefault
option add *app*popup*text*width 50 widgetDefault
option add *app*popup*text*height 10 widgetDefault
option add *app*popup*text*wrap none widgetDefault
option add *app*popup*text*font TkFixedFont widgetDefault
option add *Dialog.msg.wrapLength 5i startupFile
option add *Dialog.dtl.wrapLength 5i startupFile

namespace eval app {
    variable input ""
    variable widget; array set widget {}
    variable actions; array set actions {
        options {
            {getOption name}
        }
        users {
            {getUser user_id}
            {getUserFullInfo user_id}
            {getUserSupportInfo user_id}
        }
        chats {
            {getChat chat_id}
            {getChatAdministrators chat_id}
            {getChatAvailableMessageSenders chat_id}
            {getChatInviteLink chat_id}
            {getChatInviteLinkCounts chat_id}
            {getChatListsToAddChat chat_id}
            {getChatPinnedMessage chat_id}
            {getChatSponsoredMessages chat_id}
            {getChatStatistics chat_id is_dark 0}
        }
    }
    lappend actions(chats) [list getChatMessageByDate chat_id date [clock seconds]]
}    

proc ::app::init {} {
    CreateToplevel .app normal "explore tdjson" [namespace code quit]
    CreateScrolled .app.log listbox list
    pack [checkbutton [frame .app.logbtn].enable -text enabled -variable ::cfg::_app_log_enabled] \
            -padx 8 -anchor e
    CreateState .app.auth \
            "client id:" ::td::clientId \
            "authorization state:" ::td::authorizationState \
            "connection state:" ::td::connectionState
    CreateButtons .app.btn \
            createClient "create client" [namespace code {createClient}] \
            authAction "complete auth" [namespace code {completeAuth}] \
            showOptions "show options" [namespace code {showList options}] \
            showUsers "show users" [namespace code {showList users}] \
            showChats "show chats" [namespace code {showList chats}] \
            quit "quit" [namespace code quit]
    pack .app.log -fill both -expand true
    pack .app.logbtn -fill x
    pack .app.auth -fill x
    pack .app.btn -fill x
    bind .app.log.list <Double-1> [namespace code showLogLine]
    bind .app.log.list <Return> [namespace code showLogLine]
    set ::app::widget(log) .app.log
    set ::app::widget(auth) .app.auth
    set ::app::widget(btn) .app.btn

    foreach list {options users chats} {
        CreateToplevel .app.$list utility $list [list wm withdraw .app.$list]
        CreateScrolled .app.$list.f listbox list
        CreateButtons .app.$list.btn hide "close" [list wm withdraw .app.$list]
        pack .app.$list.f -fill both -expand true
        pack .app.$list.btn -fill x
        menu .app.$list.actions -tearoff 0
        foreach action $::app::actions($list) {
            .app.$list.actions add command -label [lindex $action 0] \
                    -command [namespace code [list InvokeListAction $list $action]]
        }
        bind .app.$list.f.list <3> \
                {%W selection clear 0 end; %W selection set @%x,%y; %W activate @%x,%y; focus %W}
        bind .app.$list.f.list <3> "+tk_popup .app.$list.actions %X %Y"
        set action [lindex $::app::actions($list) 0]
        bind .app.$list.f.list <Double-1> [namespace code [list InvokeListAction $list $action]]
        bind .app.$list.f.list <Return> [namespace code [list InvokeListAction $list $action]]
        set ::app::widget($list) .app.$list.f
    }

    set ::app::widget(input) .app.input
    set ::app::widget(popup) .app.popup

    wm deiconify .app
    focus .app
    raise .app
    update

    foreach list {options users chats} {
        ::td::setListCallback $list [namespace code [list UpdateList $list]]
    }
    ::td::setLogCallback [namespace code UpdateLog]
    ::td::receiveBgStart
}

proc ::app::done {} {
    ::td::receiveBgStart
    ::td::setLogCallback ""
    foreach list {options users chats} {
        ::td::setListCallback $list ""
    }
    ::destroy .api
    array unset ::app::widget *
}

proc ::app::quit {} {
    ::cfg::save
    exit
}

proc ::app::createClient {} {
    if {$::td::clientId ne ""} {
        messageBox "warning" warning "client already created as #$::td::clientId"
    } else {
        ::td::createClient
        send "create client" "getOption" "name" [jsonString "version"]
    }
}

proc ::app::send {title type args} {
    popup open $title "close" "sending $type..." [td::formatEvent [concat @type $type $args]]
    set extra [td::send $type {*}$args]
    while {[popup active]} {
        # popup grabs events, call receive directly
        ::td::receive $::td::receiveBgTimeout
        set response [td::received $extra]
        if {$response ne ""} {
            popup update $title "ok" "response to $type" [FormatEventJson $response]
            break
        }
        update
    }
}

proc ::app::completeAuth {} {
    set title "complete auth"
    switch -- $::td::authorizationState {
        "authorizationStateClosed" {
            tk_messageBox -parent .app -icon info -message "client is closed, create new client"
        }
        "authorizationStateWaitTdlibParameters" {
            if {[input $title "api id" ::cfg::api_id "api hash" ::cfg::api_hash]} {
                send $title "setTdlibParameters" \
                        "database_directory"   [jsonString $::cfg::database_directory] \
                        "use_message_database"             $::cfg::use_message_database \
                        "use_secret_chats"                 $::cfg::use_secret_chats \
                        "api_id"                           $::cfg::api_id \
                        "api_hash"             [jsonString $::cfg::api_hash] \
                        "system_language_code" [jsonString $::cfg::system_language_code] \
                        "device_model"         [jsonString $::cfg::device_model] \
                        "application_version"  [jsonString $::cfg::application_version] \
                        "enable_storage_optimizer"         $::cfg::enable_storage_optimizer
            }
        }
        "authorizationStateWaitPhoneNumber" {
            if {[input $title "your phone number" ::cfg::phone_number]} {
                send $title "setAuthenticationPhoneNumber" \
                        "phone_number" [jsonString $::cfg::phone_number]
            }
        }
        "authorizationStateWaitEmailAddress" {
            if {[input $title "your email address" ::cfg::email_address]} {
                send $title "setAuthenticationEmailAddress" \
                        "email_address" [jsonString $::cfg::email_address]
            }
        }
        "authorizationStateWaitEmailCode" {
            if {[input $title "email authentication code you received" ::cfg::code]} {
                send $title "emailAddressAuthenticationCode" \
                        "code" [jsonString $::cfg::code]
            }
        }
        "authorizationStateWaitCode" {
            if {[input $title "authentication code you received" ::cfg::code]} {
                send $title "checkAuthenticationCode" \
                        "code" [jsonString $::cfg::code]
            }
        }
        "authorizationStateWaitRegistration" {
            if {[input $title "your first name" ::cfg::first_name "your last name" ::cfg::last_name]} {
                send $title "registerUser" \
                        "first_name" [jsonString $::cfg::first_name] \
                        "last_name" [jsonString $::cfg::last_name]
            }
        }
        "authorizationStateWaitPassword" {
            if {[input $title "your password" ::cfg::password]} {
                send $title "checkAuthenticationPassword" \
                        "password" [jsonString $::cfg::password]
            }
        }
    }
}

proc ::app::showList {list} {
    set w [winfo toplevel $::app::widget($list)]
    expr {[winfo ismapped $w] ? [wm withdraw $w] : [wm deiconify $w; raise $w]}
}

proc ::app::showLogLine {} {
    set s [$::app::widget(log).list get active]
    set i [string first "\{" $s]
    popup open "log event" "close" [string range $s 0 [expr {$i-2}]] \
            [FormatEventJson [string range $s $i end]]
}

proc ::app::messageBox {title icon message} {
    tk_messageBox -parent .app -type ok -title $title -icon $icon -message $message
}

proc ::app::input {title args} {
    set w $::app::widget(input)
    CreateToplevel $w dialog $title {set ::app::input "cancel"}
    frame $w.ent
    set i 0
    foreach {prompt varname} $args {
        grid [label $w.ent.l$i -text $prompt -anchor e] [entry $w.ent.e$i] -pady 4 -padx 4 -sticky we
        if {[info exists $varname]} {
            $w.ent.e$i insert 0 [set $varname]
        }
        incr i
    }
    grid columnconfig $w.ent 1 -weight 1
    CreateButtons $w.btn ok "ok" {set ::app::input "ok"} cancel "cancel" {set ::app::input "cancel"}
    pack $w.ent -fill both -expand 1
    pack $w.btn -fill x
    tk::PlaceWindow $w widget .app
    wm transient $w .app
    tkwait visibility $w
    tk::SetFocusGrab $w $w.btn.ok
    vwait ::app::input
    if {$::app::input eq "ok"} {
        set i 0
        foreach {- varname} $args {
            set $varname [$w.ent.e$i get]
            incr i
        }
    }
    tk::RestoreFocusGrab $w $w.btn.ok
    expr {$::app::input eq "ok"}
}

proc ::app::popup {command args} {
    set w $::app::widget(popup)
    switch -- $command {
        open {
            set cmd [namespace code [list ::app::popup close]]
            CreateToplevel $w dialog "popup" $cmd
            CreateScrolled $w.txt text text;
            label $w.msg
            button $w.btn -command $cmd
            pack $w.msg -padx 8 -pady 8 -fill x
            pack $w.txt -fill both -expand 1
            pack $w.btn -fill x
            tk::PlaceWindow $w widget .app
            wm transient $w .app
            tkwait visibility $w
            tk::SetFocusGrab $w $w.btn
            tailcall ::app::popup update {*}$args
        }
        active {
            return [winfo exists $w]
        }
        update {
            lassign $args title button message text
            wm title $w $title
            $w.btn configure -text $button
            $w.msg configure -text $message
            $w.txt.text delete 0.0 end
            $w.txt.text insert 0.end $text
            $w.txt.text tag configure "info" -foreground blue -underline true
            $w.txt.text tag bind "info" <1> [namespace code {ShowPopupInfo @%x,%y}]
            $w.txt.text tag bind "info" <Return> [namespace code {ShowPopupInfo @%x,%y}]
            $w.txt.text tag bind "info" <Enter> {%W configure -cursor "hand2"}
            $w.txt.text tag bind "info" <Leave> {%W configure -cursor ""}
            FormatPopupText
        }
        close {
            tk::RestoreFocusGrab $w $w.btn
        }
        default {
            error "invalid ::app::popup command '$command'"
        }
    }
}

proc ::app::FormatPopupText {} {
    set w $::app::widget(popup).txt.text
    foreach i [$w search -all -regexp {@type: \w+$} 1.0] {
        $w tag add "info" $i [regsub {\d+$} $i end]
    }
}

proc ::app::ShowPopupInfo {point} {
    set indices [.app.popup.txt.text tag prevrange "info" $point+1char]
    set text [.app.popup.txt.text get {*}$indices]
    if {[regexp {@type: (\w+)$} $text => type]} {
        tk_messageBox -title "tdjson api" -message $type -detail [join [td::getDescription $type] \n\n]
    }
}

proc ::app::FormatEventJson {json} {
    if {[catch {json::json2dict $json} result]} {
        return $result\n$json
    } else {
        return [td::formatEvent $result]
    }
}

proc ::app::UpdateLog {message} {
    if {$::cfg::_app_log_enabled} {
        set end [$::app::widget(log).list index end]
        if {$end >= $::cfg::_app_log_max_lines} {
            $::app::widget(log).list delete 0 \
                    [expr {$end - $::cfg::_app_log_max_lines}]
        }
        $::app::widget(log).list insert end $message
        $::app::widget(log).list see end
    }
}

proc ::app::UpdateList {list name value} {
    $::app::widget($list).list delete 0 end
    $::app::widget($list).list insert end \
        {*}[lmap n [dict keys [set ::td::$list]] \
                {format "%s: %s" $n [dict get [set ::td::$list] $n]}]
}

proc ::app::InvokeListAction {list action} {
    set i [$::app::widget($list).list index active]
    if {$i ne "" && [regexp {^([^:]+):} [$::app::widget($list).list get $i] => v]} {
        lassign $action request n
        send "query $list: $v" $request $n [jsonString $v] {*}[lrange $action 2 end]
    }
}

proc ::app::CreateToplevel {w type title delete} {
    destroy $w
    toplevel $w
    wm withdraw $w
    wm title $w $title
    wm protocol $w WM_DELETE_WINDOW $delete
    if {$::tcl_platform(platform) eq "unix"} {
        wm attributes $w -type $type
    }
}

proc ::app::CreateScrolled {w widget name} {
    frame $w
    $widget $w.$name \
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

proc ::app::CreateState {w args} {
    frame $w
    set i 0
    foreach {label varname} $args {
        grid [label $w.l$i -text $label -anchor e] \
                [label $w.s$i -textvariable $varname -anchor w] -sticky we
        incr i
    }
}

proc ::app::CreateButtons {w args} {
    frame $w
    pack {*}[lmap {name text command} $args \
            {button $w.$name -text $text -command $command}] -fill x -side left -expand 1
}

namespace eval td {
    variable clientId ""
    variable authorizationState ""
    variable connectionState ""

    variable options [dict create]
    variable users [dict create]
    variable chats [dict create]
    variable queries [dict create]

    variable types [dict create]
    variable classes [dict create]
    variable functions [dict create]
    variable descriptions [dict create]
    variable apiFile ""

    variable logCallback "";
    variable listCallback; array set listCallback {options "" users "" chats ""}
    variable receiveBgTimeout 0.01
}

proc ::td::init {} {
    if {$::cfg::_td_api_file ne ""} {
        set ::td::apiFile [OpenApi $::cfg::_td_api_file]
    }
    td_set_log_message_callback 0 ::td::Fatal
    td_execute [jsonObject "@type" [jsonString "setLogVerbosityLevel"] "new_verbosity_level" 1]
    return ""
}

proc ::td::done {} {
    receiveBgStop
    setLogCallback ""
    array set listCallback {options "" users "" chats ""}
    set ::td::clientId ""
    set ::td::authorizationState ""
    set ::td::connectionState ""
    foreach v {options chats users queries types classes functions descriptions} {
        set ::td::$v [dict create]
    }
    catch {close $::td::apiFile}
    set ::td::apiFile ""
    td_set_log_message_callback 0
}

proc ::td::execute {type args} {
    set json [jsonObject "@type" [jsonString $type] {*}$args]
    Log "EXEC>" $json
    Parse "EXEC<" [td_execute $json]
}

proc ::td::createClient {} {
    if {$::td::clientId eq ""} {
        set ::td::clientId [td_create_client_id]
    }
}

proc ::td::send {type args} {
    if {$::td::clientId ne ""} {
        set extra [clock clicks]
        set json [jsonObject "@type" [jsonString $type] "@extra" $extra {*}$args]
        Log "SEND>" $json
        td_send $::td::clientId $json
        dict set ::td::queries $extra ""
        return $extra
    }
    return ""
}

proc ::td::receive {timeout} {
    Parse "RECV<" [td_receive $timeout]
}

proc ::td::received {extra} {
    if {[dict exists $::td::queries $extra]} {
        set event [dict get $::td::queries $extra]
        if {$event ne ""} {
            dict unset ::td::queries $extra
            return $event
        }
    }
    return ""
}

proc ::td::receiveBgStart {} {
    receive $::td::receiveBgTimeout
    update
    after idle [namespace code receiveBgStart]
}

proc ::td::receiveBgStop {} {
    after cancel [namespace code receiveBgStart]
}

proc ::td::setLogCallback {callback} {
    set ::td::logCallback $callback
}

proc ::td::setListCallback {list callback} {
    set ::td::listCallback($list) $callback
}

proc ::td::getDescription {apiname} {
    if {$::td::apiFile ne "" && [dict exists $::td::descriptions $apiname]} {
        try {
            set result ""
            seek $::td::apiFile [dict get $::td::descriptions $apiname]
            while {[gets $::td::apiFile s] >= 0} {
                if {[regexp {^\s*//(@.*)$} $s => r]} {
                    append result $r " "
                } elseif {[regexp {^\s*//-(.*)$} $s => r]} {
                    append result $r " "
                } else {
                    break
                }
            }
            return [split [string map {" @" "\n@"} $result] "\n"]
        } on error {message} {
            tk_messageBox -title "explore - api" -icon warning \
                    -message "error reading api file:\n$message"
            catch {close $::td::apiFile}
            set ::td::apiFile ""
            return ""
        }
    }
}

proc ::td::formatEvent {dict {indent 4} {level 0}} {
    set result ""
    set padding [string repeat " " [expr {$indent * $level}]]
    dict for {k v} $dict {
        set s $padding
        if {![string match "@*" $k]} {
            append s " "
        }
        set snext $s[string repeat " " $indent]
        set l [expr {$level+1}]
        if {[catch {dict get $v @type}]} {
            if {[catch {lmap i $v {dict get $i @type}}]} {
                if {[string first "\n" $v] < 0} {
                    append result [format "%s%s: %s\n" $s $k $v]
                } else {
                    append result [format "%s%s:\n%s %s\n" $s $k $snext \
                            [string map [list "\n" "\n$snext "] $v]]
                }
            } else {
                append result [format "%s%s:\n%s" $s $k \
                        [join [lmap i $v {td::formatEvent $i $indent $l}] ""]]
            }
        } else {
            append result [format "%s%s:\n%s" $s $k [td::formatEvent $v $indent $l]]
        }
    }
    return $result
}

proc ::td::Parse {info json} {
    if {$json eq ""} return
    Log $info $json
    try {
        set event [json::json2dict $json]
    } on error message {
        Log "ERROR" $message
        return ""
    }
    if {[dict exists $event "@extra"]} {
        dict set ::td::queries [dict get $event "@extra"] $json
    }
    if {[dict exists $event "@type"]} {
        switch -- [dict get $event "@type"] {
            "updateOption" {
                if {[dict exists $event "name"] && [dict exists $event "value" "value"]} {
                    set n [dict get $event "name"]
                    set v [dict get $event "value" "value"]
                    if {![dict exists $::td::options $n] || [dict get $::td::options $n] ne $v} {
                        dict set ::td::options $n $v
                        InvokeListCallback options $n $v
                    }
                }
            }
            "updateUser" {
                if {[dict exists $event "user" "id"] && \
                        [dict exists $event "user" "first_name"] && \
                        [dict exists $event "user" "last_name"]} {
                    set n [dict get $event "user" "id"]
                    set v [format "%s %s" \
                            [dict get $event "user" "first_name"] \
                            [dict get $event "user" "last_name"]]
                    if {![dict exists $::td::users $n] || [dict get $::td::users $n] ne $v} {
                        dict set ::td::users $n $v
                        InvokeListCallback users $n $v
                    }
                }
            }
            "updateNewChat" {
                if {[dict exists $event "chat" "id"] && [dict exists $event "chat" "title"]} {
                    set n [dict get $event "chat" "id"]
                    set v [dict get $event "chat" "title"]
                    if {![dict exists $::td::chats $n] || [dict get $::td::chats $n] ne $v} {
                        dict set ::td::chats $n $v
                        InvokeListCallback chats $n $v
                    }
                }
            }
            "updateAuthorizationState" {
                if {[dict exists $event "authorization_state" "@type"]} {
                    set ::td::authorizationState [dict get $event "authorization_state" "@type"]
                }
            }
            "updateConnectionState" {
                if {[dict exists $event "state" "@type"]} {
                    set ::td::connectionState [dict get $event "state" "@type"]
                }
            }
        }
    }
    return $event
}

proc td::InvokeListCallback {list name value} {
    if {$::td::listCallback($list) ne ""} {
        uplevel #0 $::td::listCallback($list) [list $name $value]
    }
}

proc ::td::OpenApi {filename} {
    variable types
    variable classes
    variable functions
    variable descriptions
    try {
        set dict types
        set f [open $filename r]
        set p [tell $f]
        set l 0
        while {[gets $f s] >= 0} {
            incr l
            set s [string trim $s]
            if {$s eq "---functions---"} {
                set dict functions
            } elseif {$s eq "---types---"} {
                set dict types
            } elseif {[regexp {^\s*//@description} $s]} {
                set d $p
            } elseif {[regexp {^\s*//@class\s+(\w+)} $s => obj]} {
                dict set descriptions $obj $p
            } elseif {[regexp {^(\w+)\s(.*)=\s*(\w+);$} $s => obj params result]} {
                set result [string trim $result]
                dict set $dict $obj [concat $params $result]
                if {$dict eq "types"} {
                    dict lappend classes $result $obj
                }
                if {[info exists d]} {
                    dict set descriptions $obj $d
                    unset d
                }
            }
            set p [tell $f]
        }
        return $f
    } on error {message} {
        tk_messageBox -title "explore - api" -icon warning \
                -message "error loading api file $filename:\n$message"
        catch {close $f}
        return ""
    }
}

proc ::td::Log {info text} {
    # debug $info:$text
    if {$::td::logCallback ne ""} {
        uplevel #0 $::td::logCallback [list [format "%s %s" $info $text]]
    }
}

proc ::td::Fatal {level message} {
    debug "tdlib message: $level $message"
    if {$level == 0} {
        ::td::done
        tk_messageBox -title "tdlib fatal error" -icon error -message $message
        exit 1
    }
}

namespace eval cfg {
    variable _debug 0
    variable _td_api_file ""
    variable _cfg_var_file ""
    variable _cfg_cfg_file ""
    variable _app_log_max_lines 1000
    variable _app_log_enabled 1
    # NOTE: defaults for auth
    variable database_directory "tdlib"
    variable use_message_database 1
    variable use_secret_chats 1
    variable system_language_code "en"
    variable device_model "Desktop"
    variable application_version "1.0"
    variable enable_storage_optimizer 1    
}

proc ::cfg::init {} {
    set rootname [file rootname [info script]]
    set ::cfg::_cfg_var_file [load [lindex $::argv 1] $rootname.var]
    set ::cfg::_cfg_cfg_file [load [lindex $::argv 0] $rootname.cfg]
    if {$::cfg::_debug} {
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

proc cfg::done {} {
    unset {*}[info vars ::cfg::*]
    variable _debug 0
    variable _td_api_file ""
    variable _cfg_var_file ""
    variable _cfg_cfg_file ""
    variable _app_log_max_lines 1000
    variable _app_log_enabled 1
}

proc ::cfg::load {fname1 fname2} {
    set fname [expr {$fname1 ne "" ? $fname1 : $fname2}]
    if {$fname1 ne "" || [file exists $fname]} {
        try {
            set f [open $fname "r"]
            foreach l [split [read $f] \n] {
                set l [string trim $l]
                if {$l ne "" && [string range $l 0 0] != "#"} {
                    variable {*}[lrange $l 0 end]
                }
            }
        } on error {message} {
            tk_messageBox -title "explore - config" -icon warning \
                    -message "error loading config file $fname:\n$message"
        } finally {
            catch {close $f}
        }
    }
    return $fname
}

proc ::cfg::save {} {
    if {$::cfg::_cfg_var_file ne ""} {
        try {
            set f [open $::cfg::_cfg_var_file "w"]
            foreach v [lsort [info vars ::cfg::*]] {
                if {[info exists $v] && [namespace tail $v] ni {password code}} {
                    puts $f [list [namespace tail $v] [set $v]]
                }
            }
        } on error {message} {
            tk_messageBox -title "explore - config" -icon warning \
                    -message "error saving config file $::cfg::_cfg_var_file:\n$message"
        } finally {
            catch {close $f}
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
    if {$::cfg::_debug} {
        puts stderr $message
    }
}

proc tkerror {args} {
    tk_messageBox -title "explore - tkerror" -icon error -message [join $args \n]
}

cfg::init
td::init
app::init
