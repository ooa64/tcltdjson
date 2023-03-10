package require Tk
package require tcltdjson
catch {package require Thread}
catch {package require yajltcl}

wm withdraw .

option add *App*log*list*width 100 widgetDefault
option add *App*log*list*height 30 widgetDefault
option add *App*auth*Entry*width 40 widgetDefault
option add *App*Objects*list*width 50 widgetDefault
option add *App*Objects*list*height 30 widgetDefault
option add *App*Popup*text*width 50 widgetDefault
option add *App*Popup*text*height 20 widgetDefault
option add *App*Popup*text*wrap none widgetDefault
option add *App*Popup*text*font TkFixedFont widgetDefault
option add *App*Request*text.width 50 widgetDefault
option add *App*Request*text.height 20 widgetDefault
option add *App*Request*text.wrap none widgetDefault
option add *App*Request*text*Entry*relief ridge widgetDefault
option add *App*Request*text*Spinbox*relief ridge widgetDefault
option add *Dialog.msg.wrapLength 5i startupFile
option add *Dialog.dtl.wrapLength 5i startupFile

bind Listbox <3> {%W selection clear 0 end; %W selection set @%x,%y; %W activate @%x,%y; focus %W}

namespace eval app {
    namespace eval request {
        variable input; array set input {}
    }
    variable widget; array set widget {}
    variable actions; array set actions {
        options {
            {getOption name}
            {setOption name}
        }
        users {
            {getUser user_id}
            {getUserFullInfo user_id}
        }
        chats {
            {getChat chat_id}
            {getChatHistory chat_id}
            {getChatPinnedMessage chat_id}
            {getChatMessageCount chat_id}
        }
        messages {
            {getMessage chat_id message_id}
            {getMessageThread chat_id message_id}
        }
    }
    lappend actions(chats) [list getChatMessageByDate chat_id date [clock seconds]]
}    

proc ::app::init {} {
    CreateToplevel .app App normal "Explore TDJSON" {::app::quit}
    CreateScrolled .app.log listbox list
    CreateState .app.auth \
            "Client Id:" ::td::clientId \
            "Authorization State:" ::td::authorizationState \
            "Connection State:" ::td::connectionState
    CreateButtons .app.btn \
            createClient "Create Client" {::app::createClient} \
            authAction "Complete Auth" {::app::completeAuth} \
            showOptions "Show Options" {::app::showObjects options} \
            showUsers "Show Users" {::app::showObjects users} \
            showChats "Show Chats" {::app::showObjects chats} \
            request "Request" {::app::request open - "Request"} \
            quit "Quit" {::quit}
    frame .app.logbtn
    button .app.logbtn.clear -text "Clear Log" -command {.app.log.list delete 0 end}
    checkbutton .app.logbtn.enabled -text "Enabled" -variable ::cfg::_app_log_enabled
    pack .app.logbtn.clear .app.logbtn.enabled -ipadx 8 -side left
    grid .app.log - - -sticky news
    grid .app.auth x .app.logbtn -sticky n
    grid .app.btn - - -sticky we
    grid columnconfigure .app 1 -weight 1
    grid rowconfigure .app 0 -weight 1
    bind .app.log.list <Double-1> {::app::showLogLine}
    bind .app.log.list <Return> {::app::showLogLine}
    set ::app::widget(log) .app.log
    set ::app::widget(auth) .app.auth
    set ::app::widget(btn) .app.btn

    foreach i {options users chats} {
        CreateToplevel .app.$i Objects utility [string totitle $i] [list wm withdraw .app.$i]
        CreateScrolled .app.$i.f listbox list
        CreateButtons .app.$i.btn hide "Hide" [list wm withdraw .app.$i]
        pack .app.$i.f -fill both -expand true
        pack .app.$i.btn -fill x
        menu .app.$i.actions -tearoff 0
        foreach action $::app::actions($i) {
            .app.$i.actions add command -label [lindex $action 0] \
                    -command [list ::app::openObjectsAction $i $action]
        }
        bind .app.$i.f.list <3> [list +tk_popup .app.$i.actions %X %Y]
        set ::app::widget($i) .app.$i.f

        ::td::setObjectsCallback $i {::app::updateObjects}
    }
    .app.chats.actions add separator
    .app.chats.actions add command -label "New Messages" -command {::app::openMessages}
    bind .app.chats.f.list <Double-1> {::app::openMessages}
    bind .app.chats.f.list <Return> {::app::openMessages}

    wm deiconify .app
    raise .app

    set ::app::widget(messages) .app.messages
    set ::app::widget(request) .app.request
    set ::app::widget(popup) .app.popup

    ::td::setLogCallback {::app::updateLog}
    ::td::startReceiveBg
}

proc ::app::createClient {} {
    if {$::td::clientId eq ""} {
        ::td::createClient
        send "Create Client" "@type" [jsonString "getOption"] "name" [jsonString "version"]
    } elseif {[tk_messageBox -parent .app -type yesno -title "warning" -icon warning \
            -message "Client already created. Destroy?"] eq "yes"} {
        send "Destroy Client" "@type" [jsonString "close"]
    }
}

proc ::app::completeAuth {} {
    if {$::td::authorizationState eq "authorizationStateClosed"} {
        tk_messageBox -parent .app -icon info -title "info" \
                -message "Client is closed, create new client"
    } elseif {$::td::authorizationState eq "authorizationStateReady"} {
        if {[tk_messageBox -parent .app -type yesno -title "warning" -icon warning \
                -message "Client already authorized, log out?"] eq yes} {
            send "Logout Client" "@type" [jsonString "logOut"]
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
            request open - "Complete Auth" "func" $map($::td::authorizationState)
        }
    }
}

proc ::app::showObjects {object} {
    ::tk::PlaceWindow [winfo toplevel $::app::widget($object)] widget .app
}

proc ::app::showLogLine {} {
    set s [$::app::widget(log).list get active]
    set i [string first "\{" $s]
    popup open - "Log Event" "Close" [string range $s 0 [expr {$i-2}]] \
            [FormatEventJson [string range $s $i end]]
}

proc ::app::popup {command w args} {
    switch -- $command {
        open {
            # args: title button message text
            if {$w ne "-"} {set wname $w; unset w; upvar $wname w}
            set w $::app::widget(popup)[::cfg::nextId]
            set close [list ::app::popup close $w]
            CreateToplevel $w Popup dialog "Popup" $close
            CreateScrolled $w.txt text text
            label $w.msg
            button $w.btn -command $close
            pack $w.msg -padx 8 -pady 8 -fill x
            pack $w.txt -fill both -expand 1
            pack $w.btn -fill x

            ::tk::PlaceWindow $w widget .app
            focus $w.btn

            tailcall ::app::popup update $w {*}$args
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
            destroy $w
        }
    }
}

proc ::app::request {command w args} {
    switch -- $command {
        open {
            # args: title name1 value1
            if {$w ne "-"} {set wname $w; unset w; upvar $wname w}
            set w $::app::widget(request)[::cfg::nextId]
            set title [lindex $args 0]
            set close [list ::app::request "close" $w]
            set select [list ::app::request::selectFunction $w.txt.text $w.btn]
            CreateToplevel $w Request dialog $title $close
            CreateScrolled $w.txt text text
            CreateButtons $w.btn \
                select "Select" $select \
                send "Send" [list ::app::request "send" $w $title] \
                load "Load" [list ::app::request::load $w] \
                save "Save" [list ::app::request::save $w] \
                close "Close" $close
            entry $w.btn.func
            menu $w.btn.menu -tearoff 0
            pack $w.btn.func -before $w.btn.select -side left
            pack $w.txt -fill both -expand yes
            pack $w.btn -fill x
            bind $w.btn.func <Return> $select
            bind $w.btn.func <FocusIn> {%W selection range 0 end}

            set bg [$w.txt.text cget -background]
            option add *App*Request*text*Entry*background $bg widgetDefault
            option add *App*Request*text*Spinbox*readonlyBackground $bg widgetDefault

            ::tk::PlaceWindow $w widget .app
            focus $w.btn.func

            request::import $w [lrange $args 1 end]
            request::configureInfo $w.txt.text "info"
        }
        send {
            # args: title
            after idle [list ::app::send [lindex $args 0] [::app::request::getJson $w.txt.text]]
            tailcall request "close" $w
        }
        close {
            set id [request::id $w]
            array unset ::app::request::input $id,*
            destroy $w
        }
    }
}

proc ::app::send {title args} {
    popup open w $title "Close" "Sending..." [FormatEventJson [jsonObject {*}$args]]
    ::td::setEventCallback [td::send {*}$args] [list apply {
        {w title extra response} {
            if {[popup active $w]} {
                popup update $w $title "Ok" "Response" [FormatEventJson $response]
            }
        } ::app
    } $w $title]
}

proc ::app::updateLog {message} {
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

proc ::app::updateObjects {objects name value} {
    set s "$name: $value"
    set w $::app::widget($objects).list
    set i [lsearch -glob [$w get 0 end] "$name: *"]
    if {$i >= 0} {
        $w delete $i
        $w insert $i $s    
    } else {
        $w insert end $s    
    }
}

proc ::app::openObjectsAction {objects action} {
    set w $::app::widget($objects).list
    if {[regexp {^([^:]+):} [$w get active] => id]} {
        lassign $action func key
        request open - "Query [string totitle $objects]: $id" "func" $func /$func/$key $id \
                {*}[join [lmap {n v} [lrange $action 2 end] {list /$func/$n $v}]]
    }
}

proc ::app::updateMessages {id name value} {
    set s [regsub -all {\s+} [regsub {^message} $value ""] " "]
    set s [string trimright [string range "$name: $s" 0 199]]
    set w $::app::widget(messages)$id.f.list
    $w insert end $s
}

proc ::app::openMessages {} {
    set w $::app::widget(chats).list
    if {[regexp {^([^:]+):\s*(.*)$} [$w get active] => id name]} {
        set w $::app::widget(messages)$id
        if {[winfo exists $w]} {
            raise $w
        } else {
            set title [string trim [regsub -all {[^\w\s]} $name ""]]
            CreateToplevel $w Objects utility "Messages: $id $title" [list wm withdraw $w]
            CreateScrolled $w.f listbox list
            CreateButtons $w.btn close "Close" [list ::app::closeMessages $id]
            pack $w.f -fill both -expand true
            pack $w.btn -fill x
            menu $w.actions -tearoff 0
            foreach action $::app::actions(messages) {
                $w.actions add command -label [lindex $action 0] \
                        -command [list ::app::openMessagesAction $id $action]
            }
            bind $w.f.list <3> [list +tk_popup $w.actions %X %Y]
            ::tk::PlaceWindow [winfo toplevel $w] widget .app
            ::td::setMessagesCallback $id {::app::updateMessages}
        }
    }
}

proc ::app::closeMessages {id} {
    set w $::app::widget(messages)$id
    ::td::setMessagesCallback $id {}
    catch {destroy $w}
}

proc ::app::openMessagesAction {id action} {
    set w $::app::widget(messages)$id
    if {[regexp {^([^:]+):} [$w.f.list get active] => messageId]} {
        lassign $action func key messageKey
        request open - "Query Messages: $id/$messageId" "func" $func \
                /$func/$key $id /$func/$messageKey $messageId \
                {*}[join [lmap {n v} [lrange $action 3 end] {list /$func/$n $v}]]
    }
}

proc ::app::CreateToplevel {w class type title delete} {
    toplevel $w -class $class
    wm withdraw $w
    wm title $w $title
    wm protocol $w WM_DELETE_WINDOW $delete
    if {[tk windowingsystem] eq "x11"} {
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
        label $w.l$i -text $label -anchor "e"
        entry $w.e$i -textvariable $varname -state readonly
        grid $w.l$i $w.e$i -sticky we
        incr i
    }
}

proc ::app::CreateButtons {w args} {
    frame $w
    pack {*}[lmap {name text command} $args {button $w.$name -text $text -command $command}] \
            -fill x -side left -expand 1
}

proc ::app::FormatEventJson {json} {
    if {[catch {jsonParse $json} result]} {
        return $result\n$json
    } else {
        return [td::formatEvent $result]
    }
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
    variable input
    set id [id $w]
    array unset input $id,/*#class
    $btn.menu delete 0 end
    $btn.func delete 0 end
    $btn.func insert end $func
    set input($id,func) $func
    foreach n [array names ::cfg::request /$func/*] {
        set input($id,$n) $::cfg::request($n)
    }

    $w configure -state normal
    $w tag delete "" {*}[lsearch -all -inline [$w tag names] "/*"]
    $w delete 1.0 end
    InsertElement $w -1 0 "" $func $func
    $w configure -state disabled
}

proc ::app::request::InsertElement {w level align parent name type} {
    variable input
    set id [id $w]
    set pad [string repeat " " [expr {$level*4}]]
    set path $parent/$name
    set script {}

    lassign [::td::getTypeInfo $name $type] class info
    set input($id,$path#class) [list $class $info]
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
                    -textvariable ::app::request::input($id,$path) \
                    -validate key -vcmd [list string is $info %P]
            $w insert insert [format "%s %-${align}s" $pad "$name:"]
            $w window create insert -window $w.$path
            $w insert insert "\n"
        }
        "array" {
            set script [list ::app::request::UpdateArray $w [expr {$level+1}] $path $info +1lines]
            spinbox $w.$path#size -width 2 -state readonly -buttoncursor "hand2" -justify right \
                    -textvariable ::app::request::input($id,$path#size) \
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
            if {[info exists input($id,$path#type)] && $input($id,$path#type) in $info} {
                set path_type $input($id,$path#type)
            }
            spinbox $w.$path#type -width 20 -state readonly -buttoncursor "hand2" \
                    -textvariable ::app::request::input($id,$path#type) \
                    -values [concat {""} $info] -wrap true \
                    -command $script
            $w insert insert [format "%s %-${align}s" $pad $name]
            $w window create insert -window $w.$path#type
            $w insert insert "\($type\):\n"
            $w tag add "info" [$w index insert-3c-[string length $type]c] [$w index insert-3c]
            set input($id,$path#type) $path_type
        }        
        "func" - "struct" {
            if {$class eq "struct"} {
                $w insert insert "$pad $name:\n"
            }
            set a [string length "@type"]
            foreach {n t} [join [lmap i $info {split $i ":"}]] {
                set a [expr {max($a,[string length $n])}]
            }
            incr a
            InsertElement $w [expr {$level+1}] $a $path "@type" $type
            foreach {n t} [join [lmap i $info {split $i ":"}]] {
                InsertElement $w [expr {$level+1}] $a $path $n $t
            }
        }
    }
    $w tag add $path $first insert
    $w tag lower $path
    # update array/union structure for predefined size/type
    {*}$script
}

proc ::app::request::UpdateArray {w level parent type offset} {
    variable input
    set id [id $w]
    set state [$w cget -state]
    $w configure -state normal

    $w mark set insert [$w index $parent.first$offset]
    set first [$w index insert]
    set tags [$w tag names]
    for {set i 0} {$i < min($input($id,$parent#size),99)} {incr i} {
        if {"$parent/$i" ni $tags} {
            InsertElement $w $level [expr {[string length $i]+1}] $parent $i $type
            # expand parent tags
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
        array unset input $id,$parent/$i*#class
        $w delete $parent/$i.first $parent/$i.last
        $w tag delete $parent/$i
    }
    $w configure -state $state
}

proc ::app::request::UpdateUnion {w level parent type offset} {
    variable input
    set id [id $w]
    set state [$w cget -state]
    $w configure -state normal

    $w mark set insert [$w index $parent.first$offset]
    set first [$w index insert]
    $w delete $first $parent.last
    array unset input $id,$parent/*#class
    if {$input($id,$parent#type) ne ""} {
        lassign [::td::getTypeInfo $type $input($id,$parent#type)] class info
        set a [string length "@type"]
        foreach {n t} [join [lmap i $info {split $i ":"}]] {
            set a [expr {max($a,[string length $n])}]
        }
        incr a
        InsertElement $w $level $a $parent "@type" $input($id,$parent#type)
        foreach {n t} [join [lmap i $info {split $i ":"}]] {
            InsertElement $w $level $a $parent $n $t
        }
        # expand parent tags
        foreach t [$w tag names $first-1char] {
            if {[string first $t $parent] == 0} {
                $w tag add $t $first insert
            }
        }
    }
    $w configure -state $state
}

proc ::app::request::getJson {w} {
    variable input
    set id [id $w]
    set json ""
    foreach {cmd txt pos} [$w dump -tag 1.0 end] {
        if {![info exists input($id,$txt#class)]} continue
        lassign $input($id,$txt#class) class info
        if {$class eq "func"} continue
        if {$class eq "value" && $input($id,$txt) eq ""} continue
        if {$class eq "union" && $input($id,$txt#type) eq ""} continue
        if {$class eq "array" && $input($id,$txt#size) eq "0"} continue
        switch -- $cmd {
            "tagon" {
                set tail [lindex [split $txt "/"] end]
                set name [lindex [split $tail "#"] 0]
                if {![string is integer $name]} {
                    append json "\"$name\":"
                }
                switch -- $class {
                    "type" {
                        append json "\"$info\","
                    }
                    "unknown" {
                        append json "\"$input($id,$txt)\","
                    }
                    "value" {
                        if {$info in {"ascii" "print"}} {
                            append json "\"$input($id,$txt)\","
                        } elseif {$input($id,$txt) ne ""} {
                            append json $input($id,$txt) ","
                        }
                    }
                    "array" {
                        append json "\["
                    }
                    "struct" - "union" {
                        append json "\{"
                    }
                }
            }
            "tagoff" {
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
    }
    return [string trimright $json ","]
}

proc ::app::request::import {w request} {
    variable input
    set id [id $w]
    set func [expr {[dict exists $request "func"] ? [dict get $request "func"] : ""}]
    foreach {n v} $request {
        if {$func eq ""} {
            set func [lindex [split [lindex [split $n /] 1] #] 0]
        }
        set input($id,$n) $v
    }
    if {$func ne ""} {
        insertFunction $w.txt.text $w.btn $func
    }
}

proc ::app::request::load {w} {
    set request [::cfg::loadRequest]
    if {[llength $request]} {
        import $w $request
    }
}

proc ::app::request::save {w} {
    variable input
    set id [id $w]
    if {[info exists input($id,func)]} {
        set request {}
        foreach n [lsort [array names input $id,/*]] {
            if {[string match "*#class" $n] || [string match "*password*" $n]} {
                continue
            }
            if {$input($n) ne ""} {
                lappend request [regsub {^\d+,} $n ""] $input($n)
            }
        }
        if {[llength $request]} {
            ::cfg::saveRequest $input($id,func) $request
        }
    }
}

proc ::app::request::id {w} {
    scan $w $::app::widget(request)%d
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
        tk_messageBox -parent $w -title "info" -message $type -detail [join [td::getDescription $type] \n\n]
    }
}

namespace eval td {
    variable clientId ""
    variable authorizationState ""
    variable connectionState ""
    variable types [dict create]
    variable classes [dict create]
    variable functions [dict create]
    variable descriptions [dict create]
    variable logFile ""
    variable apiFile ""
    variable apiBasic; array set apiBasic {
        "double" "double"
        "string" "print"
        "int32" "integer"
        "int53" "entier"
        "int64" "entier"
        "bytes" "ascii"
        "Bool" "boolean"
    }

    variable logCallback ""
    variable eventCallback; array set eventCallback {}
    variable objectsCallback; array set objectsCallback {}
    variable messagesCallback; array set messagesCallback {}

    variable receiveBgTimeout 0.01
}

proc ::td::init {} {
    if {[info commands ::yajl::json2dict] ne ""} {
        debug "using yajltcl"
        interp alias {} jsonParse {} ::yajl::json2dict
    } elseif {![catch {package require json}]} {
        debug "using tcllib"
        interp alias {} jsonParse {} ::json::json2dict
    } else {
        tkerror "JSON library not found.\nPlease install yayltcl or tcllib"
        exit
    }
    if {$::cfg::_td_log_file ne ""} {
        set ::td::logFile [OpenLog $::cfg::_td_log_file]
    }
    if {$::cfg::_td_api_file ne "" && [file exists $::cfg::_td_api_file]} {
        set ::td::apiFile [OpenApi $::cfg::_td_api_file]
    } else {
        tkwarning "The API file '$::cfg::_td_api_file' is missing.\nThe latest API file is available at" \
                "https://github.com/tdlib/td/blob/master/td/generate/scheme/td_api.tl"
    }
    if {$::td::apiFile eq ""} {
        debug "using basic descriptors"
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
    if {[info commands ::thread::create] ne ""} {
        debug "using threads"
        variable receiveBgTimeout 1.00
        variable receiveBgThread [::thread::create]
        ::thread::send $::td::receiveBgThread [list set auto_path $::auto_path]
        ::thread::send $::td::receiveBgThread [list package require tcltdjson]
    }
    td_set_log_message_callback 0 ::td::Fatal
    td_execute [jsonObject "@type" [jsonString "setLogVerbosityLevel"] "new_verbosity_level" 1]
}

proc ::td::quit {} {
    stopReceiveBg
    destroyClient
    CloseLog
}

proc ::td::createClient {} {
    set ::td::clientId [td_create_client_id]
}

proc ::td::destroyClient {} {
    set ::td::clientId ""
    set ::td::authorizationState ""
    set ::td::connectionState ""
    array unset ::td::eventCallback
}

proc ::td::execute {type args} {
    set json [jsonObject "@type" [jsonString $type] {*}$args]
    WriteLog "EXEC>" $json
    Parse "EXEC<" [td_execute $json]
}

proc ::td::send {args} {
    if {$::td::clientId ne ""} {
        set extra [clock clicks]
        set json [jsonObject "@extra" $extra {*}$args]
        WriteLog "SEND>" $json
        td_send $::td::clientId $json
        return $extra
    }
    return ""
}

proc ::td::receive {timeout} {
    if {[info exists ::td::receiveBgThread]} {
        ::thread::send -async $::td::receiveBgThread \
                [list td_receive $timeout] ::td::receiveBgResult
        vwait ::td::receiveBgResult
        Parse "RECV<" $::td::receiveBgResult
    } else {
        Parse "RECV<" [td_receive $timeout]
    }
}

proc ::td::startReceiveBg {} {
    receive $::td::receiveBgTimeout
    update
    after idle {::td::startReceiveBg}
}

proc ::td::stopReceiveBg {} {
    after cancel {::td::startReceiveBg}
}

proc ::td::setLogCallback {callback} {
    set ::td::logCallback $callback
}

proc ::td::setEventCallback {extra callback} {
    set ::td::eventCallback($extra) $callback
}

proc ::td::setObjectsCallback {objects callback} {
    if {$callback ne ""} {
        set ::td::objectsCallback($objects) $callback
    } else {
        unset ::td::objectsCallback($objects)
    }
}

proc ::td::setMessagesCallback {id callback} {
    if {$callback ne ""} {
        set ::td::messagesCallback($id) $callback
    } else {
        unset ::td::messagesCallback($id)
    }
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
    set result ""
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
            set result [split [string map {" @" "\n@"} $result] "\n"]
        } on error {message} {
            tkwarning "Error reading api file:" $message
            catch {close $::td::apiFile}
            set ::td::apiFile ""
        }
    }
    return $result
}

proc ::td::formatEvent {dict {indent 4} {level 0}} {
    set result ""
    set pad [string repeat " " [expr {$indent * $level}]]
    dict for {k v} $dict {
        set p $pad
        if {![string match "@*" $k]} {
            append p " "
        }
        set pnext $p[string repeat " " $indent]
        set lnext [expr {$level+1}]
        if {[catch {dict get $v @type}]} {
            if {[catch {lmap i $v {dict get $i @type}}]} {
                if {[string first "\n" $v] < 0} {
                    append result [format "%s%s: %s\n" $p $k $v]
                } else {
                    append result [format "%s%s:\n%s %s\n" $p $k $pnext \
                            [string map [list "\n" "\n$pnext "] $v]]
                }
            } else {
                append result [format "%s%s:\n%s" $p $k \
                        [join [lmap i $v {td::formatEvent $i $indent $lnext}] ""]]
            }
        } else {
            append result [format "%s%s:\n%s" $p $k [td::formatEvent $v $indent $lnext]]
        }
    }
    return $result
}

proc ::td::Parse {info json} {
    if {$json eq ""} return
    WriteLog $info $json
    try {
        set event [jsonParse $json]
    } on error {message} {
        WriteLog "ERROR" $message
        return ""
    }
    if {[dict exists $event "@extra"]} {
        InvokeEventCallback [dict get $event "@extra"] $json
    }
    if {[dict exists $event "@type"]} {
        switch -- [dict get $event "@type"] {
            "updateOption" {
                if {[dict exists $event "name"] && [dict exists $event "value" "value"]} {
                    InvokeObjectsCallback options \
                            [dict get $event "name"] [dict get $event "value" "value"]
                }
            }
            "updateUser" {
                if {[dict exists $event "user" "id"] && \
                        [dict exists $event "user" "first_name"] && \
                        [dict exists $event "user" "last_name"]} {
                    InvokeObjectsCallback users \
                            [dict get $event "user" "id"] [format "%s %s" \
                                    [dict get $event "user" "first_name"] \
                                    [dict get $event "user" "last_name"]]
                }
            }
            "updateNewChat" {
                if {[dict exists $event "chat" "id"] && [dict exists $event "chat" "title"]} {
                    InvokeObjectsCallback chats \
                            [dict get $event "chat" "id"] [dict get $event "chat" "title"]
                }
            }
            "updateNewMessage" {
                if {[dict exists $event "message" "chat_id"] && [dict exists $event "message" "id"]} {
                    InvokeMessagesCallback [dict get $event "message" "chat_id"] \
                            [dict get $event "message" "id"] [FormatMessageTitle $event]
                }
            }
            "updateAuthorizationState" {
                if {[dict exists $event "authorization_state" "@type"]} {
                    set ::td::authorizationState [dict get $event "authorization_state" "@type"]
                    if {$::td::authorizationState eq "authorizationStateClosed"} {
                        destroyClient
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

proc ::td::InvokeEventCallback {extra json} {
    if {[info exists ::td::eventCallback($extra)]} {
        set callback $::td::eventCallback($extra)
        unset ::td::eventCallback($extra)
        uplevel #0 $callback [list $extra $json]
    }
}

proc ::td::InvokeObjectsCallback {objects name value} {
    if {[info exists ::td::objectsCallback($objects)]} {
        uplevel #0 $::td::objectsCallback($objects) [list $objects $name $value]
    }
}

proc ::td::InvokeMessagesCallback {id name value} {
    if {[info exists ::td::messagesCallback($id)]} {
        uplevel #0 $::td::messagesCallback($id) [list $id $name $value]
    }
}

proc ::td::FormatMessageTitle {event} {
    set result {}
    if {[dict exists $event "message" "content" "@type"]} {
        lappend result [dict get $event "message" "content" "@type"]
        if {[dict exists $event "message" "content" "caption" "text"]} {
            lappend result [dict get $event "message" "content" "caption" "text"]
        } elseif {[dict exists $event "message" "content" "text" "text"]} {
            lappend result [dict get $event "message" "content" "text" "text"]
        }
    } else {
        lappend result "UNKNOWN" $event
    }
    join $result " "
}

proc ::td::OpenApi {fname} {
    variable types
    variable classes
    variable functions
    variable descriptions
    try {
        set dict "types"
        set f [open $fname r]
        set p [tell $f]
        while {[gets $f s] >= 0} {
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
        tkwarning "Error loading API file $fname:" $message
        catch {close $f}
        return ""
    }
}

proc ::td::OpenLog {fname} {
    try {
        set ::td::logFile [open $fname a]
    } on error {message} {
        tkwarning "Error opening log file $fname:" $message
    }
}

proc ::td::CloseLog {} {
    catch {close $::td::logFile}
    set ::td::logFile ""
}

proc ::td::WriteLog {info text} {
    set stamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S"]
    if {$::td::logFile ne ""} {
        try {
            puts $::td::logFile [format "%s %s %s" $stamp $info $text]
        } on error {message} {
            ::td::CloseLog
            tkwarning "Error writing log file:" $message
        }
    }
    if {$::td::logCallback ne ""} {
        uplevel #0 $::td::logCallback [list [format "%s %s" $info $text]]
    }
}

proc ::td::Fatal {level message} {
    puts stderr "tdlib message: $level $message"
    if {$level == 0} {
        ::td::quit
        tk_messageBox -title "TDLIB fatal error" -icon error -message $message
        exit 1
    }
}

namespace eval cfg {
    variable _debug 0
    variable _td_api_file ""
    variable _td_log_file ""
    variable _cfg_cfg_file ""
    variable _app_req_dir ""
    variable _app_log_max_lines 1000
    variable _app_log_enabled 1
    variable request; array set request {}
    coroutine nextId apply {{} {yield; while true {yield [incr i]}}}
}

proc ::cfg::init {args} {
    set rootname [file rootname [info script]]
    set ::cfg::_cfg_cfg_file [load [lindex $args 0] $rootname.cfg]
    if {$::cfg::_debug} {
        debug "configured from" [file normalize $::cfg::_cfg_cfg_file]
        if {$::tcl_platform(platform) eq "windows"} {
            console show
            update idletasks
            catch {
                package require dde
                dde servername ExploreDebug
                debug "ddeserver started as ExploreTcl"
            }
        }
        catch {
            package require tkconclient
            tkconclient::start 12345
            debug "tkconclient started at port 12345"
        }
    }
}

proc ::cfg::load {fname1 fname2} {
    set fname [expr {$fname1 ne "" ? $fname1 : $fname2}]
    if {$fname1 ne "" || [file exists $fname]} {
        try {
            set f [open $fname "r"]
            foreach l [split [read $f] \n] {
                set l [string trim $l]
                switch -- [string range $l 0 0] {
                    "_" {set ::cfg::[lindex $l 0] [lindex $l 1]}
                    "/" {set ::cfg::request([lindex $l 0]) [lindex $l 1]}
                }
            }
        } on error {message} {
            tkwarning "Error loading config file $fname:" $message
        } finally {
            catch {close $f}
        }
    }
    return $fname
}

proc ::cfg::loadRequest {} {
    set request {}
    set fname [tk_getOpenFile -title "Load Request" \
            -filetypes {{request *.req} {all *.*}} \
            -initialdir $::cfg::_app_req_dir \
            -defaultextension .req]
    if {$fname ne ""} {
        try {
            set f [open $fname "r"]
            foreach l [split [read $f] \n] {
                set l [string trim $l]
                if {[string range $l 0 0] eq "/"} {
                    lappend request [lindex $l 0] [lindex $l 1]
                }
            }
        } on error {message} {
            tkwarning "Error loading request file $fname:" $message
        } finally {
            catch {close $f}
        }
    }
    return $request
}

proc ::cfg::saveRequest {fname request} {
    set fname [tk_getSaveFile -title "Save Request" \
            -filetypes {{request *.req} {all *.*}} \
            -initialdir $::cfg::_app_req_dir \
            -initialfile $fname \
            -defaultextension .req]
    if {$fname ne ""} {
        try {
            set f [open $fname "w"]
            foreach {n v} $request {
                puts $f [list $n $v]
            }
        } on error {message} {
            tkwarning "Error saving request file $fname:" $message
        } finally {
            catch {close $f}
        }
    }
}

proc jsonParse {json} {#::td::init}
proc jsonArray {args} {return \[[join $args ,]\]}
proc jsonString {str} {return [join [list \" [string map {\" \\\" \n \\n \r \\r \t \\t \\ \\\\} $str] \"] ""]}
proc jsonObject {args} {
    # args: ?name0 value0? ?name1 value1? ?jsonobject?
    set result {}
    if {[llength $args] % 2} {
        foreach {n v} [lrange $args 0 end-1] {
            lappend result [jsonString $n]:$v
        }
        lappend result [lindex $args end]
    } else {
        foreach {n v} $args {
            lappend result [jsonString $n]:$v
        }
    }
    return \{[join $result ,]\}
}

proc tkwarning {args} {tk_messageBox -icon warning -title "Warning" -message [join $args \n]}
proc tkerror {args} {tk_messageBox -icon error -title "Error" -message [join $args \n]}
proc debug {args} {if {$::cfg::_debug} {puts stderr [join $args]}}

proc init {args} {
    cfg::init {*}$args
    td::init
    app::init
}

proc quit {} {
    ::td::quit
    exit
}

init {*}$argv
