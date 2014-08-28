#include "Fl_Platform.h"

#if __FLTK_WIN32__
#include "config_win32.h"
#elif __FLTK_IPHONEOS__
#include "config_ios.h"
#elif __FLTK_MACOSX__
#include "config_mac.h"
#elif __FLTK_LINUX__
#include "config_linux.h"
#elif __FLTK_WINCE__
#include "config_wince.h"
#else
#error unsupported platform
#endif
