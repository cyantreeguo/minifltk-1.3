#ifndef _Fl_TrayIcon_H
#define _Fl_TrayIcon_H

#include "Fl_Platform.h"

#if __FLTK_WIN32__

#include "Fl_Win32_TrayIcon.h"
#include "Fl_TrayPopMenu.h"

#define Fl_TrayIcon Fl_Win32_TrayIcon

#elif __FLTK_MACOSX__

#include "Fl_Mac_TrayIcon.h"
#include "Fl_TrayPopMenu.h"

#define Fl_TrayIcon Fl_Mac_TrayIcon

#elif __FLTK_LINUX__

#include "Fl_Linux_TrayIcon.h"
#include "Fl_TrayPopMenu.h"

#define Fl_TrayIcon Fl_Linux_TrayIcon

#endif

#endif
