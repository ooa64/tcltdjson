# tcl version of the python example https://github.com/tdlib/td/blob/master/example/python/tdjson_example.py

package require Ffidl

set lib "tdjson.dll"

# 1 line JSON parser from https://wiki.tcl-lang.org/page/JSON
proc json2dict {json} {
    subst -nocommands -novariables [
        string range [
            string trim [
                string trimleft [
                    string map {\t {} \n {} \r {} , { } : { } \[ \{ \] \} \\" \\\\"} $json
                ] {\uFEFF}
            ]
        ] 1 end-1
    ]
}

proc input {prompt} {
    puts -nonewline stdout $prompt
    flush stdout
    string trim [gets stdin]
}

if {[llength [info commands ::ffidl::callback]]} {
    ::ffidl::callback on_log_message_callback {int pointer-utf8} void
    ::ffidl::callout td_set_log_message_callback {int pointer-proc} void [::ffidl::symbol $lib td_set_log_message_callback]

    td_set_log_message_callback 2 on_log_message_callback

    proc on_log_message_callback {verbosity_level message} {
        if {"verbosity_level" == 0} {
            puts stderr "TDLib fatal error: $verbosity_level $message"
            exit 1
        }
    }
}

::ffidl::callout td_create_client_id {} int [::ffidl::symbol $lib td_create_client_id]
::ffidl::callout td_send {int pointer-utf8} void [::ffidl::symbol $lib td_send]
::ffidl::callout td_receive {double} pointer-utf8 [::ffidl::symbol $lib td_receive]
::ffidl::callout td_execute {pointer-utf8} pointer-utf8 [::ffidl::symbol $lib td_execute]

# setting TDLib log verbosity level to 1 (errors} $x]
puts [td_execute {{"@type": "setLogVerbosityLevel", "new_verbosity_level": 1, "@extra": 1.01234}}]

# create client
set client_id [td_create_client_id]

# another test for TDLib execute method
puts [td_execute {{"@type": "getTextEntities", "text": "@telegram /test_command https://telegram.org telegram.me", "@extra": ["5", 7.0, "a"]}}]

# start the client by sending a request to it
td_send $client_id {{"@type": "getOption", "name": "version", "@extra": 1.01234}}

# main events cycle
while {true} {
    set json [td_receive 1.0]
    puts $json

    set event [json2dict $json]
    if {[dict exists $event "@type"] \
            && [dict get $event "@type"] eq "updateAuthorizationState" \
            && [dict exists $event "authorization_state" "@type"]} {

        switch -- [dict get $event "authorization_state" "@type"] {

            "authorizationStateClosed" {
                # if client is closed, we need to destroy it and create new client
                break
            }

            "authorizationStateWaitTdlibParameters" {
                # set TDLib parameters
                # you MUST obtain your own api_id and api_hash at https://my.telegram.org
                # and use them in the setTdlibParameters call
                td_send $client_id {{"@type": "setTdlibParameters",
                     "database_directory": "tdlib",
                     "use_message_database": 1,
                     "use_secret_chats": 1,
                     "api_id": 94575,
                     "api_hash": "a3406de8d171bb422bb6ddf3bbd800e2",
                     "system_language_code": "en",
                     "device_model": "Desktop",
                     "application_version": "1.0",
                     "enable_storage_optimizer": 1}}
            }

            "authorizationStateWaitPhoneNumber" {
                # enter phone number to log in
                set phone_number [input "Please enter your phone number:  "]
                td_send $client_id [format {{"@type": "setAuthenticationPhoneNumber", "phone_number": "%s"}} $phone_number]
            }

            "authorizationStateWaitEmailAddress" {
                # enter email address to log in
                set email_address [input "Please enter your email address:  "]
                td_send $client_id [format {{"@type": "setAuthenticationEmailAddress", "email_address": "%s"}} $email_address]
            }

            "authorizationStateWaitEmailCode" {
                # wait for email authorization code
                set code [input "Please enter the email authentication code you received:  "]
                td_send $client_id [format {{"@type": "checkEmailAddressVerificationCode", "code" : "%s"}} $code]
            }

            "authorizationStateWaitCode" {
                # wait for authorization code
                set code [input "Please enter the authentication code you received:  "]
                td_send $client_id [format {{"@type": "checkAuthenticationCode", "code": "%s"}} $code]
            }

            "authorizationStateWaitRegistration" {
                # wait for first and last name for new users
                set first_name [input "Please enter your first name:  "]
                set last_name [input "Please enter your last name:  "]
                td_send $client_id [format {{"@type": "registerUser", "first_name": "%s", "last_name": "%s"}} $first_name $last_name]
            }

            "authorizationStateWaitPassword" {
                # wait for password if present
                set password [input "Please enter your password:  "]
                td_send $client_id [format {{"@type": "checkAuthenticationPassword", "password": "%s"}} $password]
            }

            default {
                continue
            }
        }
    }
    update idletasks
}
