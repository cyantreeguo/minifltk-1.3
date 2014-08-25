//
// "$Id: x.H 10158 2014-05-23 16:00:25Z manolo $"
//
// X11 header file for the Fast Light Tool Kit (FLTK).
//
// Copyright 1998-2012 by Bill Spitzak and others.
//
// This library is free software. Distribution and use rights are outlined in
// the file "COPYING" which should have been included with this file.  If this
// file is missing or damaged, see the license at:
//
//     http://www.fltk.org/COPYING.php
//
// Please report all bugs and problems on the following page:
//
//     http://www.fltk.org/str.php
//

// These are internal fltk symbols that are necessary or useful for
// calling Xlib.  You should include this file if (and ONLY if) you
// need to call Xlib directly.  These symbols may not exist on non-X
// systems.

/** \class Fl_Mac_App_Menu
 Mac OS-specific class allowing to localize the application menu.

 These character strings are used to build the application menu. They can be localized
 at run time to any UTF-8 text by placing instructions such as this \e very
 early in the program:
 \verbatim
 Fl_Mac_App_Menu::print = "Imprimer la fenêtre";
 \endverbatim
*/

#if !defined(Fl_X_H) && !defined(FL_DOXYGEN)
#  define Fl_X_H

#include "Enumerations.H"
#include "Fl_Platform.h"

#if __FLTK_WIN32__
#include "x_win32.H"
#elif __FLTK_MACOSX__
#include "x_mac.H"
#elif __FLTK_IPHONEOS__
#include "x_ios.H"
#elif __FLTK_LINUX__
#include "x_linux.h"
#else
#error unsupported platform
#endif

#endif

//
// End of "$Id: x.H 10158 2014-05-23 16:00:25Z manolo $".
//
