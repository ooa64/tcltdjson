#include <tcl.h>
#include <td/telegram/td_json_client.h>

#include "tdjson.h"
#include "tdjsonUuid.h"

/*
TDJSON_EXPORT int td_create_client_id();
TDJSON_EXPORT void td_send(int client_id, const char *request);
TDJSON_EXPORT const char *td_receive(double timeout);
TDJSON_EXPORT const char *td_execute(const char *request);
typedef void (*td_log_message_callback_ptr)(int verbosity_level, const char *message);
TDJSON_EXPORT void td_set_log_message_callback(int max_verbosity_level, td_log_message_callback_ptr callback);
*/

static int CreateClientId_Cmd(void *clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    if (objc == 1) {
        Tcl_SetObjResult(interp, Tcl_NewIntObj(td_create_client_id()));
        return TCL_OK;
    } else {
        Tcl_WrongNumArgs(interp, 1, objv, NULL);
        return TCL_ERROR;
    }
}

static int Send_Cmd(void *clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    if (objc == 3) {
        int client_id;
        if (Tcl_GetIntFromObj(interp, objv[1], &client_id) != TCL_OK) {
            return TCL_ERROR;
        }
        td_send(client_id, Tcl_GetString(objv[2]));
        return TCL_OK;
    } else {
        Tcl_WrongNumArgs(interp, 1, objv, "client_id request");
        return TCL_ERROR;
    }
}

static int Execute_Cmd(void *clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    if (objc == 2) {
        Tcl_SetObjResult(interp, Tcl_NewStringObj(td_execute(Tcl_GetString(objv[1])), -1));
        return TCL_OK;
    } else {
        Tcl_WrongNumArgs(interp, 1, objv, "request");
        return TCL_ERROR;
    }
}

static int Receive_Cmd(void *clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    if (objc == 2) {
        double timeout;
        if (Tcl_GetDoubleFromObj(interp, objv[1], &timeout) != TCL_OK) {
            return TCL_ERROR;
        }
        Tcl_SetObjResult(interp, Tcl_NewStringObj(td_receive(timeout), -1));
        return TCL_OK;
    } else {
        Tcl_WrongNumArgs(interp, 1, objv, "timeout");
        return TCL_ERROR;
    }
}

#ifndef STRINGIFY
#  define STRINGIFY(x) STRINGIFY1(x)
#  define STRINGIFY1(x) #x
#endif

#ifdef __cplusplus
extern "C" {
#endif  /* __cplusplus */
DLLEXPORT int
Tdjson_Init(
    Tcl_Interp* interp)		/* Tcl interpreter */
{
    Tcl_CmdInfo info;

    /*
     * This may work with 8.0, but we are using strictly stubs here,
     * which requires 8.1.
     */
    if (Tcl_InitStubs(interp, "8.1", 0) == NULL) {
	return TCL_ERROR;
    }

    if (Tcl_GetCommandInfo(interp, "::tcl::build-info", &info)) {
	Tcl_CreateObjCommand(interp, "::tdjson::build-info",
		info.objProc, (void *)(
		    PACKAGE_VERSION "+" STRINGIFY(TDJSON_VERSION_UUID)
#if defined(__clang__) && defined(__clang_major__)
			    ".clang-" STRINGIFY(__clang_major__)
#if __clang_minor__ < 10
			    "0"
#endif
			    STRINGIFY(__clang_minor__)
#endif
#if defined(__cplusplus) && !defined(__OBJC__)
			    ".cplusplus"
#endif
#ifndef NDEBUG
			    ".debug"
#endif
#if !defined(__clang__) && !defined(__INTEL_COMPILER) && defined(__GNUC__)
			    ".gcc-" STRINGIFY(__GNUC__)
#if __GNUC_MINOR__ < 10
			    "0"
#endif
			    STRINGIFY(__GNUC_MINOR__)
#endif
#ifdef __INTEL_COMPILER
			    ".icc-" STRINGIFY(__INTEL_COMPILER)
#endif
#ifdef TCL_MEM_DEBUG
			    ".memdebug"
#endif
#if defined(_MSC_VER)
			    ".msvc-" STRINGIFY(_MSC_VER)
#endif
#ifdef USE_NMAKE
			    ".nmake"
#endif
#ifndef TCL_CFG_OPTIMIZED
			    ".no-optimize"
#endif
#ifdef __OBJC__
			    ".objective-c"
#if defined(__cplusplus)
			    "plusplus"
#endif
#endif
#ifdef TCL_CFG_PROFILED
			    ".profile"
#endif
#ifdef PURIFY
			    ".purify"
#endif
#ifdef STATIC_BUILD
			    ".static"
#endif
		), NULL);
    }

    /* Provide the current package */

    if (Tcl_PkgProvideEx(interp, PACKAGE_NAME, PACKAGE_VERSION, NULL) != TCL_OK) {
	return TCL_ERROR;
    }
    Tcl_CreateObjCommand(interp, "td_create_client_id", (Tcl_ObjCmdProc *)CreateClientId_Cmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "td_execute", (Tcl_ObjCmdProc *)Execute_Cmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "td_send", (Tcl_ObjCmdProc *)Send_Cmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "td_receive", (Tcl_ObjCmdProc *)Receive_Cmd, NULL, NULL);

    return TCL_OK;
}
#ifdef __cplusplus
}
#endif  /* __cplusplus */
