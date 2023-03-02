lappend auto_path [file join [file dirname [info script]] ..] [file join [file dirname [info script]] .. win]

package require Tk
package require json
package require tdjson

wm withdraw .

foreach i {options users chats} {
    option add *app*$i*list*width 50 widgetDefault
    option add *app*$i*list*height 30 widgetDefault
    unset i
}
option add *app*log*list*width 100 widgetDefault
option add *app*log*list*height 30 widgetDefault
option add *app*input*Entry*width 50 widgetDefault
option add *app*popup*text*width 50 widgetDefault
option add *app*popup*text*height 20 widgetDefault
option add *app*popup*text*wrap none widgetDefault
option add *app*popup*text*font TkFixedFont widgetDefault
option add *app*request*text.width 50 widgetDefault
option add *app*request*text.height 20 widgetDefault
option add *app*request*text.wrap none widgetDefault
option add *app*request*text.font TkFixedFont widgetDefault
option add *Dialog.msg.wrapLength 5i startupFile
option add *Dialog.dtl.wrapLength 5i startupFile

namespace eval app {
    namespace eval request {}
    variable widget; array set widget {}
    variable actions; array set actions {
        options {
            {getOption name}
            {setOption name}
        }
        users {
            {getUser user_id}
            {getUserFullInfo user_id}
            {getUserProfilePhotos user_id offset 0 limit 99}
            {getUserSupportInfo user_id}
        }
        chats {
            {getChat chat_id}
            {getChatHistory chat_id}
            {getChatPinnedMessage chat_id}
            {getChatSponsoredMessages chat_id}
            {getChatStatistics chat_id is_dark 0}
        }
    }
    lappend actions(chats) [list getChatMessageByDate chat_id date [clock seconds]]
}    

proc ::app::init {} {
    CreateToplevel .app normal "explore tdjson" {::app::quit}
    CreateScrolled .app.log listbox list
    pack [checkbutton [frame .app.logbtn].enable -text enabled -variable ::cfg::_app_log_enabled] \
            -padx 8 -anchor e
    CreateState .app.auth \
            "client id:" ::td::clientId \
            "authorization state:" ::td::authorizationState \
            "connection state:" ::td::connectionState
    CreateButtons .app.btn \
            createClient "create client" {::app::createClient} \
            authAction "complete auth" {::app::completeAuth} \
            showOptions "show options" {::app::showList options} \
            showUsers "show users" {::app::showList users} \
            showChats "show chats" {::app::showList chats} \
            request "request" {::app::request open request} \
            quit "quit" {::app::quit}
    pack .app.log -fill both -expand true
    pack .app.logbtn .app.auth .app.btn -fill x
    bind .app.log.list <Double-1> {::app::showLogLine}
    bind .app.log.list <Return> {::app::showLogLine}
    set ::app::widget(log) .app.log
    set ::app::widget(auth) .app.auth
    set ::app::widget(btn) .app.btn

    foreach i {options users chats} {
        CreateToplevel .app.$i utility $i [list wm withdraw .app.$i]
        CreateScrolled .app.$i.f listbox list
        CreateButtons .app.$i.btn hide "close" [list wm withdraw .app.$i]
        pack .app.$i.f -fill both -expand true
        pack .app.$i.btn -fill x
        menu .app.$i.actions -tearoff 0
        foreach action $::app::actions($i) {
            .app.$i.actions add command -label [lindex $action 0] \
                    -command [list ::app::InvokeListAction $i $action]
        }
        bind .app.$i.f.list <3> \
                {%W selection clear 0 end; %W selection set @%x,%y; %W activate @%x,%y; focus %W}
        bind .app.$i.f.list <3> \
                [list +tk_popup .app.$i.actions %X %Y]
        ::td::setListCallback $i [list ::app::UpdateList $i]
        set ::app::widget($i) .app.$i.f
    }

    set ::app::widget(request) .app.request
    set ::app::widget(popup) .app.popup

    wm deiconify .app
    raise .app

    ::td::setLogCallback {::app::UpdateLog}
    ::td::receiveBgStart
}

proc ::app::quit {} {
    ::cfg::save
    exit
}

proc ::app::createClient {} {
    if {$::td::clientId eq ""} {
        ::td::createClient
        send "create client" "@type" [jsonString "getOption"] "name" [jsonString "version"]
    } elseif {[tk_messageBox -parent .app -type yesno -title warning -icon warning \
            -message "client already created. destroy?"] eq "yes"} {
        send "destroy client" "@type" [jsonString "close"]
    }
}

proc ::app::completeAuth {} {
    if {$::td::authorizationState eq "authorizationStateClosed"} {
        tk_messageBox -parent .app -icon info -message "client is closed, create new client"
    } elseif {$::td::authorizationState eq "authorizationStateClosed"} {
        if {[tk_messageBox -parent .app -type yesno -title warning -icon warning \
                -message "client already authorized. logout?"] eq yes} {
            send "logout client" "@type" [jsonString "logOut"]
        }
    } else {
        array set map {
            "authorizationStateWaitTdlibParameters" "setTdlibParameters"
            "authorizationStateWaitPhoneNumber" "setAuthenticationPhoneNumber"
            "authorizationStateWaitEmailAddress" "setAuthenticationEmailAddress"
            "authorizationStateWaitEmailCode" "checkAuthenticationEmailCode"
            "authorizationStateWaitCode" "checkAuthenticationCode"
            "authorizationStateWaitRegistration" "registerUser"
            "authorizationStateWaitPassword" "checkAuthenticationPassword"
        }
        if {[info exists map($::td::authorizationState)]} {
            request open "auth" "func" $map($::td::authorizationState)
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

proc ::app::popup {command args} {
    set w $::app::widget(popup)
    switch -- $command {
        open {
            # args: title button message text
            set close {::app::popup close}
            CreateToplevel $w dialog "popup" $close
            CreateScrolled $w.txt text text
            label $w.msg
            button $w.btn -command $close
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
            $w.txt.text configure -state normal
            $w.txt.text delete 0.0 end
            $w.txt.text insert 0.end $text
            $w.txt.text configure -state disabled
            foreach i [$w.txt.text search -all -regexp {@type: \w+$} 1.0] {
                $w.txt.text tag add "info" ${i}+7c ${i}lineend
            }
            request::configureInfo $w.txt.text "info"
        }
        close {
            tk::RestoreFocusGrab $w $w.btn
            destroy $w
        }
        default {
            error "invalid ::app::popup command '$command'"
        }
    }
}

proc ::app::request {command args} {
    set w $::app::widget(request)
    switch -- $command {
        open {
            # args: title name1 value1
            set title [lindex $args 0]
            set select [list ::app::request::selectFunction $w.txt.text $w.btn]
            set send [list ::app::request "send" $title]
            set close [list ::app::request "close"]
            CreateToplevel $w dialog $title $close
            CreateScrolled $w.txt text text
            frame $w.btn
            entry $w.btn.func
            menu $w.btn.menu -tearoff 0
            button $w.btn.select -text "select" -pady 0 -command $select
            button $w.btn.send -text "send" -pady 0 -command $send
            button $w.btn.close -text "close" -command $close
            pack $w.btn.func $w.btn.select $w.btn.send $w.btn.close -side left -fill x -expand yes
            pack $w.txt -fill both -expand yes
            pack $w.btn -fill x
            bind $w.btn.func <Return> $select
            bind $w.btn.func <FocusIn> {%W selection from 0; %W selection to end}

            tk::PlaceWindow $w widget .app
            wm transient $w .app
            tkwait visibility $w
            tk::SetFocusGrab $w $w.btn.func

            set bg [$w.txt.text cget -background]
            option add *app*request*text*Entry*background $bg widgetDefault
            option add *app*request*text*Spinbox*readonlyBackground $bg widgetDefault
            foreach {n v} [lrange $args 1 end] {
                set ::cfg::request($n) $v
            }
            if {[info exists ::cfg::request(func)]} {
                request::insertFunction $w.txt.text $w.btn $::cfg::request(func)
            }
            request::configureInfo $w.txt.text "info"
        }
        send {
            # args: title
            after idle [list ::app::send [lindex $args 0] [::app::request::getJson $w.txt.text]]
            tailcall request close
        }
        close {
            tk::RestoreFocusGrab $w $w.btn.func
            destroy $w
        }
        default {
            error "invalid ::app::request command '$command'"
        }
    }
}

proc ::app::send {title args} {
    popup open $title "close" "sending..." [FormatEventJson [jsonObject {*}$args]]
    set extra [td::send {*}$args]
    while {[popup active]} {
        # popup grabs events, call receive directly
        ::td::receive $::td::receiveBgTimeout
        set response [td::received $extra]
        if {$response ne ""} {
            popup update $title "ok" "response" [FormatEventJson $response]
            break
        }
        update
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
        set w $::app::widget(log).list
        set last [$w index end]
        if {$last >= $::cfg::_app_log_max_lines} {
            $w delete 0 [expr {$last - $::cfg::_app_log_max_lines}]
        }
        if {[lindex [$w yview] 1] == 1.0} {
            after idle [list $w see end]    
        }
        $w insert end $message
    }
}

proc ::app::UpdateList {list name value} {
    set s "$name: $value"
    set w $::app::widget($list).list
    set i [lsearch -glob [$w get 0 end] "$name: *"]
    if {$i >= 0} {
        $w delete $i
        $w insert $i $s    
    } else {
        $w insert end $s    
    }
}

proc ::app::InvokeListAction {list action} {
    set w $::app::widget($list).list
    set i [$w index active]
    if {$i ne "" && [regexp {^([^:]+):} [$w get $i] => id]} {
        lassign $action func key
        request open "query $list: $id" "func" $func /$func/$key $id \
                {*}[join [lmap {n v} [lrange $action 2 end] {list /$func/$n $v}]]
    }
}

proc ::app::CreateToplevel {w type title delete} {
#   destroy $w
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
        grid [label $w.l$i -text $label -anchor "e"] \
                [label $w.s$i -textvariable $varname -anchor "w"] -sticky we
        incr i
    }
}

proc ::app::CreateButtons {w args} {
    frame $w
    pack {*}[lmap {name text command} $args \
            {button $w.$name -text $text -command $command}] -fill x -side left -expand 1
}

proc ::app::request::selectFunction {w btn} {
    set func [$btn.func get]
    set funcs [dict keys $::td::functions $func*]
    if {[llength $funcs] == 1} {
        insertFunction $w $btn [lindex $funcs 0]
    } elseif {[llength $funcs] >= 2} {
        $btn.menu delete 0 end
        foreach i [lsort $funcs]  {
            $btn.menu add command -label $i -command \
                    [list ::app::request::insertFunction $w $btn $i]
        }
        tk_popup $btn.menu [winfo rootx $btn.select] [winfo rooty $btn.select]
    }
}

proc ::app::request::insertFunction {w btn func} {
    array unset ::cfg::request /*#class
    $btn.func delete 0 end
    $btn.func insert end $func
    set ::cfg::request(func) $func

    $w configure -state normal
    $w tag delete "" {*}[lsearch -all -inline [$w tag names] "/*"]
    $w delete 1.0 end
    InsertElement $w 0 0 "" $func $func
    $w configure -state disabled
}

proc ::app::request::InsertElement {w level align parent name type} {
    set pad [string repeat " " [expr {$level*4}]]
    set path $parent/$name
    set script {}

    lassign [::td::getTypeInfo $name $type] class info
    set ::cfg::request($path#class) [list $class $info]
    set first [$w index insert]
    switch -- $class {
        "type" {
#           $w insert insert [format "%s%-${align}s $info\n" $pad "$name:"]
            $w insert insert "$pad$name: $info\n"
            $w tag add "info" [$w index insert-1c-[string length $info]c] [$w index insert-1c]
        }
        "value" - "unknown" {
            if {$class eq "unknown"} {
                set info "print"
            }
            entry $w.$path -width 20 \
                    -textvariable ::cfg::request($path) \
                    -validate key -vcmd [list string is $info %P]
            $w insert insert [format "%s %-${align}s" $pad "$name:"]
            $w window create insert -window $w.$path
            $w insert insert "\n"
        }
        "array" {
            set script [list ::app::request::UpdateArray $w [expr {$level+1}] $path $info +1lines]
            spinbox $w.$path#size -width 2 -state readonly -buttoncursor "hand2" -justify right \
                    -textvariable ::cfg::request($path#size) \
                    -to 99.0 -format %.0f -wrap false \
                    -command $script                    
            $w insert insert [format "%s %-${align}s" $pad $name]
            $w window create insert -window $w.$path#size
            $w insert insert ":\n"
        }
        "union" {
            set script [list ::app::request::UpdateUnion $w [expr {$level+1}] $path $name +1lines]
            # spinbox resets textvariable to the first values element, save predefined value
            set path_type ""
            if {[info exists ::cfg::request($path#type)] && $::cfg::request($path#type) in $info} {
                set path_type $::cfg::request($path#type)
            }
            spinbox $w.$path#type -width 20 -state readonly -buttoncursor "hand2" \
                    -textvariable ::cfg::request($path#type) \
                    -values [concat {""} $info] -wrap true \
                    -command $script
            $w insert insert [format "%s %-${align}s" $pad $name]
            $w window create insert -window $w.$path#type
            $w insert insert "\($type\):\n"
            $w tag add "info" [$w index insert-3c-[string length $type]c] [$w index insert-3c]
            set ::cfg::request($path#type) $path_type
        }        
        "func" - "struct" {
            if {$class eq "struct"} {
                $w insert insert "$pad $name:\n"
            }
#           set a [string length "@type"]
            set a 0
            foreach {n t} [join [lmap i $info {split $i ":"}]] {
                set a [expr {max($a,[string length $n])}]
            }
            incr a
            InsertElement $w [expr {$level+1}] $a $path "@type" $type
            foreach {n t} [join [lmap i $info {split $i ":"}]] {
                InsertElement $w [expr {$level+1}] $a $path $n $t
            }
        }
        default {
            error "Internal error: invalid class '$class'"
        }
    }
    $w tag add $path $first insert
    $w tag lower $path
    # update array/union structure for predefined size/type
    {*}$script
}

proc ::app::request::UpdateArray {w level parent type offset} {
    set state [$w cget -state]
    $w configure -state normal

    $w mark set insert [$w index $parent.first$offset]
    set first [$w index insert]
    set tags [$w tag names]
    for {set i 0} {$i < $::cfg::request($parent#size)} {incr i} {
        if {"$parent/$i" ni $tags} {
            InsertElement $w $level [expr {[string length $i]+1}] $parent $i $type
            # NOTE: parent tags expantion
            foreach t [$w tag names $first-1char] {
                if {[string first $t $parent] == 0} {
                    $w tag add $t $first insert
                }
            }
            set first [$w index insert]
        } else {
            $w mark set insert [$w index $parent/$i.last]
            set first [$w index insert]
        }
    }
    for {} {"$parent/$i" in $tags} {incr i} {
        array unset ::cfg::request $parent/$i*#class
        $w delete $parent/$i.first $parent/$i.last
        $w tag delete $parent/$i
    }
    $w configure -state $state
}

proc ::app::request::UpdateUnion {w level parent type offset} {
    set state [$w cget -state]
    $w configure -state normal

    $w mark set insert [$w index $parent.first$offset]
    set first [$w index insert]
    array unset ::cfg::request $parent/*#class
    $w delete $first $parent.last
    if {$::cfg::request($parent#type) ne ""} {
        lassign [::td::getTypeInfo $type $::cfg::request($parent#type)] class info
        set a [string length "@type"]
        foreach {n t} [join [lmap i $info {split $i ":"}]] {
            set a [expr {max($a,[string length $n])}]
        }
        incr a
        InsertElement $w $level $a $parent "@type" $::cfg::request($parent#type)
        foreach {n t} [join [lmap i $info {split $i ":"}]] {
            InsertElement $w $level $a $parent $n $t
        }
        # NOTE: parent tags expantion
        foreach t [$w tag names $first-1char] {
            if {[string first $t $parent] == 0} {
                $w tag add $t $first insert
            }
        }
    }
    $w configure -state $state
}

proc ::app::request::getJson {w} {
    set json ""
    foreach {cmd txt pos} [$w dump -tag 1.0 end] {
        if {![info exists ::cfg::request($txt#class)]} {
            continue
        }
        lassign $::cfg::request($txt#class) class info
        if {$cmd eq "tagon"} {
            if {$class eq "func"} {
                continue
            }
            if {$class eq "value" && $::cfg::request($txt) eq ""} {
                continue
            }
            set path [lindex [split $txt "/"] end]
            set name [lindex [split $path "#"] 0]
            if {![string is integer $name]} {
                append json "\"$name\":"
            }
            switch -- $class {
                "type" {
                    append json "\"$info\","
                }
                "unknown" {
                    append json "\"$::cfg::request($txt)\","
                }
                "value" {
                    if {$info in {"ascii" "print"}} {
                        append json "\"$::cfg::request($txt)\","
                    } elseif {$::cfg::request($txt) ne ""} {
                        append json $::cfg::request($txt) ","
                    }
                }
                "array" {
                    append json "\["
                }
                "struct" - "union" {
                    append json "\{"
                }
            }
        } elseif {$cmd eq "tagoff"} {
            switch -- $class {
                "array" {
                    set json [string trimright $json ","]\],
                }
                "struct" - "union" {
                    set json [string trimright $json ","]\},
                }
            }    
        }
    }
    return [string trimright $json ","]
}

proc ::app::request::configureInfo {w tag} {
    $w tag configure $tag -underline true ;# -foreground blue
    $w tag bind $tag <Enter> {%W configure -cursor "question_arrow"}
    $w tag bind $tag <Leave> {%W configure -cursor ""}
    $w tag bind $tag <1> {::app::request::showInfo %W @%x,%y}
}

proc ::app::request::showInfo {w point} {
    set indices [$w tag prevrange "info" $point+1char]
    set text [$w get {*}$indices]
    if {[regexp {@type:\s*(\w+)$} $text => type] || [regexp {^(\w+)$} $text => type]} {
        tk_messageBox -title "tdjson api" -message $type -detail [join [td::getDescription $type] \n\n]
    }
}

namespace eval td {
    variable clientId ""
    variable authorizationState ""
    variable connectionState ""
    variable queries [dict create]
    variable types [dict create]
    variable classes [dict create]
    variable functions [dict create]
    variable descriptions [dict create]
    variable apiFile "td_api.tl"
    variable apiBasic; array set apiBasic {
        "double" "double"
        "string" "print"
        "int32" "integer"
        "int53" "entier"
        "int64" "entier"
        "bytes" "ascii"
        "Bool" "boolean"
    }

    variable logCallback "";
    variable listCallback; array set listCallback {options "" users "" chats ""}

    variable receiveBgTimeout 0.01
}

proc ::td::init {} {
    if {[file exists $::cfg::_td_api_file]} {
        set ::td::apiFile [OpenApi $::cfg::_td_api_file]
    } else {
        tk_messageBox -title "warning" -icon warning \
                -message "api file '$::cfg::_td_api_file' is missing, \
functionality will be limited.\
latest api file is available on github\n\
https://github.com/tdlib/td/blob/master/td/generate/scheme/td_api.tl"
        dict set ::td::functions "setTdlibParameters" {
            api_id:int32
            api_hash:string
            system_language_code:string
            device_model:string
            application_version:string
            Ok
        }
        dict set ::td::functions "setAuthenticationPhoneNumber" {phone_number:string Ok}
        dict set ::td::functions "setAuthenticationEmailAddress" {email_address:string Ok}
        dict set ::td::functions "checkAuthenticationEmailCode" {code:EmailAddressAuthentication Ok}
        dict set ::td::functions "checkAuthenticationCode" {code:string Ok}
        dict set ::td::functions "checkAuthenticationPassword" {password:string Ok}
        dict set ::td::functions "registerUser" {first_name:string last_name:string Ok}
        dict set ::td::types "emailAddressAuthenticationCode" {code:string EmailAddressAuthentication}
        dict set ::td::types "emailAddressAuthenticationAppleId" {token:string EmailAddressAuthentication}
        dict set ::td::types "emailAddressAuthenticationGoogleId" {token:string EmailAddressAuthentication}
        dict set ::td::classes "EmailAddressAuthentication" {
            emailAddressAuthenticationCode
            emailAddressAuthenticationAppleId
            emailAddressAuthenticationGoogleId
        }
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
    foreach v {queries types classes functions descriptions} {
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
    set ::td::clientId [td_create_client_id]
}

proc ::td::destroyClient {} {
    set ::td::clientId ""
}

proc ::td::send {args} {
    if {$::td::clientId ne ""} {
        set extra [clock clicks]
        set json [jsonObject "@extra" $extra {*}$args]
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
    after idle {::td::receiveBgStart}
}

proc ::td::receiveBgStop {} {
    after cancel {::td::receiveBgStart}
}

proc ::td::setLogCallback {callback} {
    set ::td::logCallback $callback
}

proc ::td::setListCallback {list callback} {
    set ::td::listCallback($list) $callback
}

proc ::td::getTypeInfo {apiname apitype} {
    if {$apiname eq "@type"} {
        return [list "type" $apitype]
    } elseif {$apitype in [array names ::td::apiBasic]} {
        return [list "value" $::td::apiBasic($apitype)]
    } elseif {[regexp {vector<(\w+)>} $apitype => vapitype]} {
        return [list "array" $vapitype]
    } elseif {[dict exists $::td::classes $apitype]} {
        return [list "union" [dict get $::td::classes $apitype]]
    } elseif {[dict exists $::td::types $apitype]} {
        return [list "struct" [lrange [dict get $::td::types $apitype] 0 end-1]]
    } elseif {[dict exists $::td::functions $apitype]} {
        return [list "func" [lrange [dict get $::td::functions $apitype] 0 end-1]]
    } else {
        return [list "unknown" $apitype]
    }
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
                    InvokeListCallback options \
                            [dict get $event "name"] [dict get $event "value" "value"]
                }
            }
            "updateUser" {
                if {[dict exists $event "user" "id"] && \
                        [dict exists $event "user" "first_name"] && \
                        [dict exists $event "user" "last_name"]} {
                    InvokeListCallback users \
                            [dict get $event "user" "id"] [format "%s %s" \
                                    [dict get $event "user" "first_name"] \
                                    [dict get $event "user" "last_name"]]
                }
            }
            "updateNewChat" {
                if {[dict exists $event "chat" "id"] && [dict exists $event "chat" "title"]} {
                    InvokeListCallback chats \
                            [dict get $event "chat" "id"] [dict get $event "chat" "title"]
                }
            }
            "updateAuthorizationState" {
                if {[dict exists $event "authorization_state" "@type"]} {
                    set ::td::authorizationState [dict get $event "authorization_state" "@type"]
                    if {$::td::authorizationState eq "authorizationStateClosed"} {
                        ::td::destroyClient
                    }
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
        set dict "types"
        set f [open $filename r]
        set p [tell $f]
        set l 0
        while {[gets $f s] >= 0} {
            incr l
            set s [string trim $s]
            if {$s eq "---functions---"} {
                set dict "functions"
            } elseif {$s eq "---types---"} {
                set dict "types"
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
    variable request; array set request {}
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
    variable request; array set request {}
}

proc ::cfg::load {fname1 fname2} {
    set fname [expr {$fname1 ne "" ? $fname1 : $fname2}]
    if {$fname1 ne "" || [file exists $fname]} {
        try {
            set f [open $fname "r"]
            foreach l [split [read $f] \n] {
                set l [string trim $l]
                switch -- [string range $l 0 0] {
                    "_" {
                        set ::cfg::[lindex $l 0] [lrange $l 1 end]
                    }
                    "/" {
                        set ::cfg::request([lindex $l 0]) [lrange $l 1 end]
                    }
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
            foreach v [lsort [info vars ::cfg::_*]] {
                if {[info exists $v]} {
                    puts $f [list [namespace tail $v] [set $v]]
                }
            }
            foreach v [lsort [array names ::cfg::request /*]] {
                if {[string match "*password*" $v]} {
                    continue
                }
                if {$::cfg::request($v) eq ""} {
                    continue
                }
                if {![string match "*#*" $v] || \
                        [string match "*#type" $v] || \
                        [string match "*#size" $v]} {
                    puts $f [list $v $::cfg::request($v)]
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
