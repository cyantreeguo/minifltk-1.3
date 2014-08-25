//
// "$Id: fl_set_fonts.cxx 8864 2011-07-19 04:49:30Z greg.ercolano $"
//
// More font utilities for the Fast Light Tool Kit (FLTK).
//
// Copyright 1998-2010 by Bill Spitzak and others.
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

#include "Fl.H"
#include "x.H"
#include "Fl_Font.H"
#include "flstring.h"
#include <stdlib.h>

#ifdef WIN32
#  include "Platform_win32_fl_set_fonts.cxxprivate"
#elif defined(__APPLE__)
#  include "Platform_mac_fl_set_fonts.cxxprivate"
#elif USE_XFT
#  include "Platform_linux_xft_fl_set_fonts.cxxprivate"
#else
#  include "Platform_linux_x_fl_set_fonts.cxxprivate"
#endif // WIN32

//
// End of "$Id: fl_set_fonts.cxx 8864 2011-07-19 04:49:30Z greg.ercolano $".
//
