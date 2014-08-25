#ifndef Fl_TrayPopMenu_H
#define Fl_TrayPopMenu_H

#include "Fl_Menu_.H"
#include "Fl_Menu_Window.H"

class FL_EXPORT Fl_TrayPopMenu : public Fl_Menu_
{
protected:
	void draw()
	{
	}
public:	
	const Fl_Menu_Item* popup(Fl_Window *w)
	{
		if ( size() < 1 ) return NULL;

		if ( isshow_ == 1 ) {
			return NULL;
		}
		isshow_ = 1;

#if __FLTK_WIN32__
		//Fl::focus(w);
		SetForegroundWindow(fl_xid(w));
		//SetFocus(fl_xid(w));
		//w->activate();
#endif
		const Fl_Menu_Item* m;
		int x, y;
		Fl::get_mouse(x, y);
		m = pulldown(w, x, y);

		picked(m);

		isshow_ = 0;
		return m;
	}

	Fl_TrayPopMenu(int X=0,int Y=0,int W=0,int H=0,const char *l=0) : Fl_Menu_(X,Y,W,H,l)
	{
		isshow_ = 0;
	}

	unsigned char IsShow()
	{
		return isshow_;
	}

protected:
	const Fl_Menu_Item* pulldown(Fl_Window *w, int X, int Y) const;

private:
	unsigned char isshow_;
};

#endif
