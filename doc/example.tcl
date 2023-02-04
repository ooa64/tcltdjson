package require tdjson

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

# setting TDLib log verbosity level to 1 (errors)
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
   puts JSON:$json

   set event [json2dict $json]
   puts DICT:$event

   if {[dict exists $event "@type"] && [dict get $event "@type"] eq "updateAuthorizationState"} {
       set auth_state_type [dict get $event "authorization_state" "@type"]

       # if client is closed, we need to destroy it and create new client
       if {$auth_state_type eq "authorizationStateClosed"} {
           break
       }

       # set TDLib parameters
       # you MUST obtain your own api_id and api_hash at https://my.telegram.org
       # and use them in the setTdlibParameters call
       if {$auth_state_type eq "authorizationStateWaitTdlibParameters"} {
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
   }
   update idle
}
