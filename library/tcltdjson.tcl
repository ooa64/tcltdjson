package require Ffidl

namespace eval ::tcltdjson {
    namespace export td_create_client_id td_send td_receive td_execute td_set_log_message_callback
    variable td_log_message_callback ""

    set lib "tdjson.dll"

    ::ffidl::callout td_create_client_id {} int [::ffidl::symbol $lib td_create_client_id]
    ::ffidl::callout td_send {int pointer-utf8} void [::ffidl::symbol $lib td_send]
    ::ffidl::callout td_receive {double} pointer-utf8 [::ffidl::symbol $lib td_receive]
    ::ffidl::callout td_execute {pointer-utf8} pointer-utf8 [::ffidl::symbol $lib td_execute]
    ::ffidl::callout Td_set_log_message_callback {int pointer-proc} void [::ffidl::symbol $lib td_set_log_message_callback]
    ::ffidl::callback [namespace code Td_log_message_callback] {int pointer-utf8} void

    proc td_set_log_message_callback {max_verbosity_level callback} {
        variable td_log_message_callback
        set _td_log_message_callback $callback
        if {$callback ne ""} {
            Td_set_log_message_callback $max_verbosity_level [namespace code Td_log_message_callback]
        } else {
            Td_set_log_message_callback $max_verbosity_level [::ffidl::info NULL]
        }
    }

    proc Td_log_message_callback {verbosity_level message} {
        variable td_log_message_callback
        if {$td_log_message_callback ne ""} {
            $td_log_message_callback $verbosity_level $message
        }
    }
}

namespace import ::tcltdjson::*

package provide tcltdjson 0.1
