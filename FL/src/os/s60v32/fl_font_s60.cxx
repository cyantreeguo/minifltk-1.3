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

#include "Fl_Font.H"
#include <FL/x.H>
#include <utf.h>
#include <string.h>

int fl_font_;
int fl_fontsize_;

void fl_font(int font, int fontsize)
	{
	// TODO: S60
	fl_font_ = font;
	fl_fontsize_ = fontsize;
	if (fl_fonts != NULL && Fl_X::WsScreenDevice != NULL)
		{		
		int fontattr = font % 4;
		font /= 4;
		TBuf16<128> fontname_;
		// TInt err;
		CnvUtfConverter::ConvertToUnicodeFromUtf8(fontname_, TPtr8((unsigned char*) fl_fonts[font].fontname, strlen(fl_fonts[font].fontname)));
		TFontSpec fontSpec(fontname_, fontsize);
		TFontStyle fontStyle(
				(fontattr == FL_ITALIC || fontattr == FL_BOLD_ITALIC) ? EPostureItalic : EPostureUpright,
				(fontattr == FL_BOLD || fontattr == FL_BOLD_ITALIC) ? EStrokeWeightBold : EStrokeWeightNormal,
				EPrintPosNormal);
		fontSpec.iFontStyle = fontStyle;
		Fl_X::WsScreenDevice->GetNearestFontInPixels(Fl_X::Font, fontSpec);
		/* if (err != KErrNone)
			{
			fontSpec.iFontStyle=TFontStyle();
			} */
		}
	if (fl_window != NULL)
		{
		Fl_X::WindowGc->UseFont(Fl_X::Font);
		}
	}

int fl_height()
	{
	// DONE: S60
	return Fl_X::Font->HeightInPixels();
	}

int fl_descent()
	{
	return Fl_X::Font->DescentInPixels();
	}

double fl_width(char const *str, int len)
	{
	// DONE: S60
	// if (len == 0) len = strlen(str);
	TPtrC8 ptr8 ((const unsigned char*) str, len);
	HBufC *buf = NULL;
	TRAPD(error, buf = CnvUtfConverter::ConvertToUnicodeFromUtf8L(ptr8));
	double w = 0;
	if (buf)
		{
		w = Fl_X::Font->TextWidthInPixels(buf->Des());
		delete buf;
		}
	return w;
	}

double fl_width(unsigned int c)
	{
	unsigned short c16 = c;
	TPtrC ptr16 (&c16, 1);
	return Fl_X::Font->TextWidthInPixels(ptr16);
	}

void fl_text_extents(const char *c, int n, int &dx, int &dy, int &w, int &h)
	{
	// TODO: S60
	}

void fl_draw(char const *str, int len, int x, int y)
	{
	// DONE: S60
	// if (len == 0) len = strlen(str);
	TPtrC8 ptr8 ((const unsigned char*) str, len);
	HBufC *buf = NULL;
	TRAPD(error, buf = CnvUtfConverter::ConvertToUnicodeFromUtf8L(ptr8));
	if (buf)
		{
		Fl_X::WindowGc->DrawText (buf->Des(), TPoint(x,y));
		delete buf;
		}
	}
