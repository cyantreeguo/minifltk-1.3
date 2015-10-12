// FLTK Symbian port Copyright 2009 by Sadysta.
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Library General Public
// License as published by the Free Software Foundation; either
// version 2 of the License, or (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Library General Public License for more details.
//
// You should have received a copy of the GNU Library General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
// USA.

#include <FL/Fl.H>
#include <FL/x.H>

static unsigned fl_cmap[256] = {
#include "fl_cmap.h" // this is a file produced by "cmap.cxx":
};

Fl_Color fl_color_;

void fl_color(Fl_Color i)
	{
	// DONE: S60
	fl_color_ = i;
	TRgb color;
	if ((i & 0xFFFFFF00) != 0) // RGB part specified
		{
		color = TRgb((i >> 8), 255);
		} else
			{
			color = TRgb(fl_cmap[i & 0xFF] >> 8, 255);
			}
	
	Fl_X::WindowGc->SetBrushColor(color);
	Fl_X::WindowGc->SetPenColor(color);
	}

void Fl::set_color(Fl_Color c, unsigned int rgb)
	{
	// DONE: S60
	fl_cmap[c] = rgb;
	}
