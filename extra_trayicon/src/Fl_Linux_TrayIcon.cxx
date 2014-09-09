#include "../Fl_Linux_TrayIcon.h"

#if __FLTK_LINUX__

#include <stdio.h>
#include "Fl_Window.H"

#include "../Fl_TrayPopMenu.h"

static Fl_Group *group;

class IconWindow : public Fl_Window {
public:
    IconWindow(void cb(Fl_Linux_TrayIcon::TrayMouseType tmt, void *X), void *X, int x, int y, int w, int h, const char* title = 0) : Fl_Window(x, y, w, h, title)
	{
	    m_cb.callback = cb;
        m_cb.x = X;

	    activemousehover_ = 0;
	}
	void ActiveMouseHover(unsigned char active)
	{
	    activemousehover_ = active;
	}
	int handle(int e)
	{
		if ( e == FL_ENTER ) {
		    if ( 0 == activemousehover_ ) return 1;
			callback(Fl_Linux_TrayIcon::tmt_MOUSEHOVER);
			return 1;
		}

		if ( e == FL_LEAVE ) {
		    if ( 0 == activemousehover_ ) return 1;
		    callback(Fl_Linux_TrayIcon::tmt_MOUSELEAVE);
			return 1;
		}

		if ( e == FL_PUSH ) {
		    int key = Fl::event_button();
		    int clicks = Fl::event_clicks();
		    if ( key == FL_LEFT_MOUSE ) {
		        if ( clicks == 0 ) callback(Fl_Linux_TrayIcon::tmt_LBUTTONDOWN);
		        else callback(Fl_Linux_TrayIcon::tmt_LBUTTONDBLCLK);
		        return 1;
		    } else if ( key == FL_RIGHT_MOUSE ) {
		        if ( clicks == 0 ) callback(Fl_Linux_TrayIcon::tmt_RBUTTONDOWN);
		        else callback(Fl_Linux_TrayIcon::tmt_RBUTTONDBLCLK);
		        return 1;
		    } else if ( key == FL_MIDDLE_MOUSE ) {
		        if ( clicks == 0 ) callback(Fl_Linux_TrayIcon::tmt_MBUTTONDOWN);
		        else callback(Fl_Linux_TrayIcon::tmt_MBUTTONDBLCLK);
		        return 1;
		    }
		}

		if ( e == FL_RELEASE ) {
		    int key = Fl::event_button();
		    if ( key == FL_LEFT_MOUSE ) {
		        callback(Fl_Linux_TrayIcon::tmt_LBUTTONUP);
		        return 1;
		    } else if ( key == FL_RIGHT_MOUSE ) {
		        callback(Fl_Linux_TrayIcon::tmt_RBUTTONUP);
		        return 1;
		    } else if ( key == FL_MIDDLE_MOUSE ) {
		        callback(Fl_Linux_TrayIcon::tmt_MBUTTONUP);
		        return 1;
		    }
		}

		return Fl_Window::handle(e);
	}

	unsigned char SetIcon(Fl_Image *img)
	{
	    group->image(0);
	    group->image(img);
	    redraw();
	    return 1;
	}

protected:
    struct {
		void (*callback)(Fl_Linux_TrayIcon::TrayMouseType tmt, void *x);
		void *x;
	} m_cb;
	void callback(Fl_Linux_TrayIcon::TrayMouseType tmt)
	{
		if ( m_cb.callback == 0 ) return;
		m_cb.callback(tmt, m_cb.x);
	}
private:
    unsigned char activemousehover_;
};

static Fl_Window *static_win_;
static Window static_window;
static IconWindow *static_traywin_;

Fl_Linux_TrayIcon::Fl_Linux_TrayIcon(Fl_Window *win, void cb(TrayMouseType tmt, void *x), void *x, unsigned char ActiveMouseHover)
{
	win_ = win;
	if ( win_ != NULL ) window_ = fl_xid(win_);

	activemousehover_ = ActiveMouseHover;
	m_cb.callback = cb;
	m_cb.x = x;

	traywin_ = NULL;
	traywindow_ = 0;

	static_win_ = win_;
	static_window = fl_xid(static_win_);
	static_traywin_ = NULL;

	m_timeruning = 0;
	imgnum_ = 0;
	m_nCurrentIconIndex = 0;
}

void Fl_Linux_TrayIcon::CreateTrayWin(char *Tooltip, Fl_Image *img)
{
	traywin_ = new IconWindow(cb_iconwindow, this, 0, 0, 1, 1);
	//traywin_->clear_border();
	if ( Tooltip != NULL ) traywin_->copy_tooltip(Tooltip);
	traywin_->color(FL_BLACK);//WhitePixel(fl_display, fl_screen));
	traywin_->box(FL_FLAT_BOX);
	traywin_->begin();
	group = new Fl_Group(0, 0, 1, 1);
	group->image(img);
	group->align(FL_ALIGN_INSIDE);
	group->end();
	traywin_->resizable(*group);
	traywin_->end();
	traywin_->show();

	Fl::wait();
	XUnmapWindow(fl_display, fl_xid(traywin_));
	XFlush(fl_display);
	Fl::wait();

	traywindow_ = fl_xid(traywin_);
	static_traywin_ = (IconWindow*)traywin_;

	static_traywin_->ActiveMouseHover(activemousehover_);

}

unsigned char Fl_Linux_TrayIcon::DockIcon()
{
    Screen* const screen = XDefaultScreenOfDisplay (fl_display);
	const int screenNumber = XScreenNumberOfScreen (screen);

	char screenAtom[32];
	sprintf(screenAtom, "_NET_SYSTEM_TRAY_S%d", screenNumber);
	Atom selectionAtom = XInternAtom (fl_display, screenAtom, False);

	//printf("select atom=%d\n", selectionAtom);

	XGrabServer (fl_display);
	managerWin_ = XGetSelectionOwner(fl_display, selectionAtom);
	if (managerWin_ != None)
		XSelectInput (fl_display, managerWin_, StructureNotifyMask | PropertyChangeMask);
	XUngrabServer (fl_display);
	XFlush (fl_display);

	//Fl::add_handler(cb_tray);
	if (managerWin_ != None) {
		XEvent ev = { 0 };
		ev.xclient.type = ClientMessage;
		ev.xclient.window = managerWin_;
		ev.xclient.message_type = XInternAtom (fl_display, "_NET_SYSTEM_TRAY_OPCODE", False);
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = CurrentTime;
		ev.xclient.data.l[1] = 0; //SYSTEM_TRAY_REQUEST_DOCK
		ev.xclient.data.l[2] = traywindow_;
		ev.xclient.data.l[3] = 0;
		ev.xclient.data.l[4] = 0;
		XSendEvent (fl_display, managerWin_, False, NoEventMask, &ev);
		XSync (fl_display, False);
	} else {
		Delete();
		return 0;
	}

	// For older KDE's ...
	long atomData = 1;
	Atom trayAtom = XInternAtom (fl_display, "KWM_DOCKWINDOW", false);
	XChangeProperty (fl_display, traywindow_, trayAtom, trayAtom, 32, PropModeReplace, (unsigned char*) &atomData, 1);

	// For more recent KDE's...
	trayAtom = XInternAtom (fl_display, "_KDE_NET_WM_SYSTEM_TRAY_WINDOW_FOR", false);
	XChangeProperty (fl_display, traywindow_, trayAtom, XA_WINDOW, 32, PropModeReplace, (unsigned char*) &traywindow_, 1);

	// A minimum size must be specified for GNOME and Xfce, otherwise the icon is displayed with a width of 1
	XSizeHints* hints = XAllocSizeHints();
	hints->flags = PMinSize;
	hints->min_width = 22;
	hints->min_height = 22;
	XSetWMNormalHints (fl_display, traywindow_, hints);
	XFree (hints);

	return 1;
}

void Fl_Linux_TrayIcon::ActiveMouseHover(unsigned char active)
{
    activemousehover_ = active;
    static_traywin_->ActiveMouseHover(activemousehover_);
}

unsigned char Fl_Linux_TrayIcon::SetIcon(Fl_Image *img)
{
    return ((IconWindow*)traywin_)->SetIcon(img);
}

#endif // #if __FLTK_LINUX__
