#include "Fl.H"
#include "fl_draw.H"
#include "../Fl_TrayPopMenu.h"
#include <stdio.h>
#include "src/flstring.h"

static unsigned char killfocus_=0;
static int owenevent(int event, Fl_Window *w)
{
	if ( event == FL_UNFOCUS ) {
		killfocus_ = 1;
		/*
		printf("unfocus\n");
		Fl_Window *w = Fl::grab();
		int r;
		Fl::grab(0);
		r = Fl::handle_(event, w);
		Fl::grab(w);
		return r;
		*/
	}

	return Fl::handle_(event, w);
}

#define TRAY_LEADING 4 // extra vertical leading

// each vertical menu has one of these:
class traymenuwindow : public Fl_Menu_Window
{
	void draw()
	{
		if (damage() != FL_DAMAGE_CHILD) {	// complete redraw
			fl_draw_box(box(), 0, 0, w(), h(), /*button ? button->color() :*/ color());
			if (menu) {
				const Fl_Menu_Item* m;
				int j;
				for (m=menu->first(), j=0; m->text; j++, m = m->next()) drawentry(m, j, 0);
			}
		} else {
			if (damage() & FL_DAMAGE_CHILD && selected!=drawn_selected) { // change selection
				drawentry(menu->next(drawn_selected), drawn_selected, 1);
				drawentry(menu->next(selected), selected, 1);
			}
		}
		drawn_selected = selected;
	}

	void drawentry(const Fl_Menu_Item* m, int n, int eraseit)
	{
		if (!m) return; // this happens if -1 is selected item and redrawn

		int BW = Fl::box_dx(box());
		int xx = BW;
		int W = w();
		int ww = W-2*BW-1;
		int yy = BW+1+n*itemheight;
		int hh = itemheight - TRAY_LEADING;

		if (eraseit && n != selected) {
			fl_push_clip(xx+1, yy-(TRAY_LEADING-2)/2, ww-2, hh+(TRAY_LEADING-2));
			draw_box(box(), 0, 0, w(), h(), /*button ? button->color() :*/ color());
			fl_pop_clip();
		}

		m->draw(xx, yy, ww, hh, 0, n==selected);

		// the shortcuts and arrows assume fl_color() was left set by draw():
		if (m->submenu()) {
			int sz = (hh-7)&-2;
			int y1 = yy+(hh-sz)/2;
			int x1 = xx+ww-sz-3;
			fl_polygon(x1+2, y1, x1+2, y1+sz, x1+sz/2+2, y1+sz/2);
		} else if (m->shortcut_) {
			Fl_Font f = m->labelsize_ || m->labelfont_ ? (Fl_Font)m->labelfont_ :
				//button ? button->textfont() : FL_HELVETICA;
				FL_HELVETICA;
		fl_font(f, m->labelsize_ ? m->labelsize_ :
			//button ? button->textsize() : FL_NORMAL_SIZE);
			FL_NORMAL_SIZE);
		const char *k, *s = fl_shortcut_label(m->shortcut_, &k);
		if (fl_utf_nb_char((const unsigned char*)k, (int) strlen(k))<=4) {
			// righ-align the modifiers and left-align the key
			char buf[32];
			strcpy(buf, s);
			buf[k-s] = 0;
			fl_draw(buf, xx, yy, ww-shortcutWidth, hh, FL_ALIGN_RIGHT);
			fl_draw(  k, xx+ww-shortcutWidth, yy, shortcutWidth, hh, FL_ALIGN_LEFT);
		} else {
			// right-align to the menu
			fl_draw(s, xx, yy, ww-4, hh, FL_ALIGN_RIGHT);
		}
		}

		if (m->flags & FL_MENU_DIVIDER) {
			fl_color(FL_DARK3);
			fl_xyline(BW-1, yy+hh+(TRAY_LEADING-2)/2, W-2*BW+2);
			fl_color(FL_LIGHT3);
			fl_xyline(BW-1, yy+hh+((TRAY_LEADING-2)/2+1), W-2*BW+2);
		}
	}
public:
	//menutitle* title;
	int handle(int);
#if defined (__APPLE__) || defined (USE_X11)
	int early_hide_handle(int);
#endif
	int itemheight;	// zero == menubar
	int numitems;
	int selected;
	int drawn_selected;	// last redraw has this selected
	int shortcutWidth;
	const Fl_Menu_Item* menu;
	traymenuwindow(Fl_Window *win, const Fl_Menu_Item* m, int X, int Y, int scr_x, int scr_y, int scr_w, int scr_h) : Fl_Menu_Window(X, Y, 0, 0, 0)
	{
		//this->parent(win);
		end();
		fl_cursor(FL_CURSOR_DEFAULT);
		//set_modal();
		clear_border();
		box(FL_BORDER_BOX);
		color(FL_WHITE);

		menu = m;
		if (m) m = m->first(); // find the first item that needs to be rendered
		drawn_selected = -1;
		selected = -1;

		int j = 0;
		if (m) for (const Fl_Menu_Item* m1=m; ; m1 = m1->next(), j++) {
			if (!m1->text) break;
		}
		numitems = j;
		itemheight = 1;

		int hotKeysw = 0;
		int hotModsw = 0;
		int Wtitle = 0;
		int Htitle = 0;
		int W = 0;
		if (m) for (; m->text; m = m->next()) {
			int hh;
			int w1 = m->measure(&hh, 0);
			if (hh+TRAY_LEADING>itemheight) itemheight = hh+TRAY_LEADING;
			if ( m->flags & (FL_SUBMENU | FL_SUBMENU_POINTER) ) w1 += FL_NORMAL_SIZE;
			if (w1 > W) W = w1;
			// calculate the maximum width of all shortcuts
			if (m->shortcut_) {
				// s is a pointerto the utf8 string for the entire shortcut
				// k points only to the key part (minus the modifier keys)
				const char *k, *s = fl_shortcut_label(m->shortcut_, &k);
				if (fl_utf_nb_char((const unsigned char*)k, (int) strlen(k))<=4) {
					// a regular shortcut has a right-justified modifier followed by a left-justified key
					w1 = int(fl_width(s, (int) (k-s)));
					if (w1 > hotModsw) hotModsw = w1;
					w1 = int(fl_width(k))+4;
					if (w1 > hotKeysw) hotKeysw = w1;
				} else {
					// a shortcut with a long modifier is right-justified to the menu
					w1 = int(fl_width(s))+4;
					if (w1 > (hotModsw+hotKeysw)) {
						hotModsw = w1-hotKeysw;
					}
				}
			}
			if (m->labelcolor_ || Fl::scheme() || m->labeltype_ > FL_NO_LABEL) clear_overlay();
		}
		shortcutWidth = hotKeysw;
		int BW = Fl::box_dx(box());
		W += hotKeysw + hotModsw + 2*BW + 7;
		if (Wtitle > W) W = Wtitle;
		w(W);
		if ( X > (scr_w-scr_x) / 2 ) X = X-W;
		x(X);
		
		h((numitems ? itemheight*numitems-TRAY_LEADING : 0) + 2*BW + 3);
		if ( Y > (scr_h-scr_y) / 2 ) Y = Y-h();
		y(Y);
	}

	traymenuwindow(Fl_Window *win, const Fl_Menu_Item* m, int X, int Y, int Wp, int Hp, int scr_x, int scr_y, int scr_w, int scr_h) : Fl_Menu_Window(X, Y, Wp, Hp, 0)
	{
		//this->parent(win);
		end();
		fl_cursor(FL_CURSOR_ARROW); // add by cyantree
		//set_modal();
		clear_border();
		box(FL_BORDER_BOX);
		color(FL_WHITE);

		menu = m;
		if (m) m = m->first(); // find the first item that needs to be rendered
		drawn_selected = -1;
		selected = -1;

		int j = 0;
		if (m) for (const Fl_Menu_Item* m1=m; ; m1 = m1->next(), j++) {
			if (!m1->text) break;
		}
		numitems = j;
		itemheight = 1;

		int hotKeysw = 0;
		int hotModsw = 0;
		int Wtitle = 0;
		int Htitle = 0;
		int W = 0;
		if (m) for (; m->text; m = m->next()) {
			int hh;
			int w1 = m->measure(&hh, 0);
			if (hh+TRAY_LEADING>itemheight) itemheight = hh+TRAY_LEADING;
			if (m->flags&(FL_SUBMENU|FL_SUBMENU_POINTER))
				w1 += FL_NORMAL_SIZE;
			if (w1 > W) W = w1;
			// calculate the maximum width of all shortcuts
			if (m->shortcut_) {
				// s is a pointerto the utf8 string for the entire shortcut
				// k points only to the key part (minus the modifier keys)
				const char *k, *s = fl_shortcut_label(m->shortcut_, &k);
				if (fl_utf_nb_char((const unsigned char*)k, (int) strlen(k))<=4) {
					// a regular shortcut has a right-justified modifier followed by a left-justified key
					w1 = int(fl_width(s, (int) (k-s)));
					if (w1 > hotModsw) hotModsw = w1;
					w1 = int(fl_width(k))+4;
					if (w1 > hotKeysw) hotKeysw = w1;
				} else {
					// a shortcut with a long modifier is right-justified to the menu
					w1 = int(fl_width(s))+4;
					if (w1 > (hotModsw+hotKeysw)) {
						hotModsw = w1-hotKeysw;
					}
				}
			}
			if (m->labelcolor_ || Fl::scheme() || m->labeltype_ > FL_NO_LABEL) clear_overlay();
		}
		shortcutWidth = hotKeysw;
		if (selected >= 0 && !Wp) X -= W/2;
		int BW = Fl::box_dx(box());
		W += hotKeysw+hotModsw+2*BW+7;
		if (Wp > W) W = Wp;
		if (Wtitle > W) W = Wtitle;

		w(W);
		if ( scr_w-scr_x - W + 1 < X+Wp ) x(X-W-1);
		else x(X+W+1);
		
		h((numitems ? itemheight*numitems-TRAY_LEADING : 0)+2*BW+3);
		// if the menu hits the bottom of the screen, we try to draw
		// it above the menubar instead. We will not adjust any menu
		// that has a selected item.
		if (Y+h()>scr_y+scr_h && Y-h()>=scr_y) {
			if (Hp>1) {
				// if we know the height of the Fl_Menu_, use it
				Y = Y-h()+Hp;
			}
		}
		if (m) y(Y);
		else {
			y(Y-2);
			w(1);
			h(1);
		}
	}

	~traymenuwindow()
	{
		hide();
		//delete title;
	}

	void set_selected(int n)
	{
		if (n != selected) {
			selected = n;
			damage(FL_DAMAGE_CHILD);
		}
	}

	int find_selected(int mx, int my)
	{
		if (!menu || !menu->text) return -1;
		mx -= x();
		my -= y();
		if (my < 0 || my >= h()) return -1;
		if (!itemheight) { // menubar
			int xx = 3;
			int n = 0;
			const Fl_Menu_Item* m = menu ? menu->first() : 0;
			for (; ; m = m->next(), n++) {
				if (!m->text) return -1;
				xx += m->measure(0, 0) + 16;
				if (xx > mx) break;
			}
			return n;
		}
		if (mx < Fl::box_dx(box()) || mx >= w()) return -1;
		int n = (my-Fl::box_dx(box())-1)/itemheight;
		if (n < 0 || n>=numitems) return -1;
		return n;
	}

	// return horizontal position for item n in a menubar:
	int titlex(int n)
	{
		const Fl_Menu_Item* m;
		int xx = 3;
		for (m=menu->first(); n--; m = m->next()) xx += m->measure(0, 0) + 16;
		return xx;
	}

	// scroll so item i is visible on screen
	void autoscroll(int n)
	{
		int scr_y, scr_h;
		int Y = y()+Fl::box_dx(box())+2+n*itemheight;

		int xx, ww;
		Fl::screen_work_area(xx, scr_y, ww, scr_h);
		if (Y <= scr_y) Y = scr_y-Y+10;
		else {
			Y = Y+itemheight-scr_h-scr_y;
			if (Y < 0) return;
			Y = -Y-10;
		}
		Fl_Menu_Window::position(x(), y()+Y);
		// y(y()+Y); // don't wait for response from X
	}

	void position(int X, int Y)
	{
		Fl_Menu_Window::position(X, Y);
		// x(X); y(Y); // don't wait for response from X
	}
	
	// return 1, if the given root coordinates are inside the window
	int is_inside(int mx, int my)
	{
		if ( mx < x_root() || mx >= x_root() + w() || my < y_root() || my >= y_root() + h()) {
				return 0;
		}
		if (itemheight == 0 && find_selected(mx, my) == -1) {
			// in the menubar but out from any menu header
			return 0;
		}
		return 1;
	}
};

////////////////////////////////////////////////////////////////
// Fl_Menu_Item::popup(...)

// Because Fl::grab() is done, all events go to one of the menu windows.
// But the handle method needs to look at all of them to find out
// what item the user is pointing at.  And it needs a whole lot
// of other state variables to determine what is going on with
// the currently displayed menus.
// So the main loop (handlemenu()) puts all the state in a structure
// and puts a pointer to it in a static location, so the handle()
// on menus can refer to it and alter it.  The handle() method
// changes variables in this state to indicate what item is
// picked, but does not actually alter the display, instead the
// main loop does that.  This is because the X mapping and unmapping
// of windows is slow, and we don't want to fall behind the events.

// values for menustate.state:
#define INITIAL_STATE 0	// no mouse up or down since popup() called
#define PUSH_STATE 1	// mouse has been pushed on a normal item
#define DONE_STATE 2	// exit the popup, the current item was picked
#define MENU_PUSH_STATE 3 // mouse has been pushed on a menu title

struct menustate {
	const Fl_Menu_Item* current_item; // what mouse is pointing at
	int menu_number; // which menu it is in
	int item_number; // which item in that menu, -1 if none
	traymenuwindow* p[20]; // pointers to menus
	int nummenus;
	int menubar; // if true p[0] is a menubar
	int state;
	// return 1 if the coordinates are inside any of the traymenuwindows
	int is_inside(int mx, int my)
	{
		int i;
		for (i=nummenus-1; i>=0; i--) {
			if (p[i]->is_inside(mx, my))
				return 1;
		}
		//printf("no in side\n");
		return 0;
	}
};
static menustate* p=0;

static inline void setitem(const Fl_Menu_Item* i, int m, int n)
{
	p->current_item = i;
	p->menu_number = m;
	p->item_number = n;
}

static void setitem(int m, int n)
{
	menustate &pp = *p;
	pp.current_item = (n >= 0) ? pp.p[m]->menu->next(n) : 0;
	pp.menu_number = m;
	pp.item_number = n;
}

static int forward(int menu)   // go to next item in menu menu if possible
{
	menustate &pp = *p;
	// Fl_Menu_Button can generate menu=-1. This line fixes it and selectes the first item.
	if (menu==-1)
		menu = 0;
	traymenuwindow &m = *(pp.p[menu]);
	int item = (menu == pp.menu_number) ? pp.item_number : m.selected;
	while (++item < m.numitems) {
		const Fl_Menu_Item* m1 = m.menu->next(item);
		if (m1->activevisible()) {
			setitem(m1, menu, item);
			return 1;
		}
	}
	return 0;
}

static int backward(int menu)   // previous item in menu menu if possible
{
	menustate &pp = *p;
	traymenuwindow &m = *(pp.p[menu]);
	int item = (menu == pp.menu_number) ? pp.item_number : m.selected;
	if (item < 0) item = m.numitems;
	while (--item >= 0) {
		const Fl_Menu_Item* m1 = m.menu->next(item);
		if (m1->activevisible()) {
			setitem(m1, menu, item);
			return 1;
		}
	}
	return 0;
}

int traymenuwindow::handle(int e)
{
#if defined (__APPLE__) || defined (USE_X11)
	// This off-route takes care of the "detached menu" bug on OS X.
	// Apple event handler requires that we hide all menu windows right
	// now, so that Carbon can continue undisturbed with handling window
	// manager events, like dragging the application window.
	int ret = early_hide_handle(e);
	menustate &pp = *p;
	if (pp.state == DONE_STATE) {
		hide();
		int i = pp.nummenus;
		while (i>0) {
			traymenuwindow *mw = pp.p[--i];
			if (mw) {
				mw->hide();
			}
		}
	}
	return ret;
}

int traymenuwindow::early_hide_handle(int e)
{
#endif
	//printf("e=%d\n", e);
	menustate &pp = *p;
	switch (e) {
	case FL_KEYBOARD:
		switch (Fl::event_key()) {
		case FL_BackSpace:
BACKTAB:
			if (!backward(pp.menu_number)) {
				pp.item_number = -1;
				backward(pp.menu_number);
			}
			return 1;
		case FL_Up:
			if (pp.menubar && pp.menu_number == 0) {
				// Do nothing...
			} else if (backward(pp.menu_number)) {
				// Do nothing...
			} else if (pp.menubar && pp.menu_number==1) {
				setitem(0, pp.p[0]->selected);
			}
			return 1;
		case FL_Tab:
			if (Fl::event_shift()) goto BACKTAB;
		case FL_Down:
			if (pp.menu_number || !pp.menubar) {
				if (!forward(pp.menu_number) && Fl::event_key()==FL_Tab) {
					pp.item_number = -1;
					forward(pp.menu_number);
				}
			} else if (pp.menu_number < pp.nummenus-1) {
				forward(pp.menu_number+1);
			}
			return 1;
		case FL_Right:
			if (pp.menubar && (pp.menu_number<=0 || (pp.menu_number==1 && pp.nummenus==2)))
				forward(0);
			else if (pp.menu_number < pp.nummenus-1) forward(pp.menu_number+1);
			return 1;
		case FL_Left:
			if (pp.menubar && pp.menu_number<=1) backward(0);
			else if (pp.menu_number>0)
				setitem(pp.menu_number-1, pp.p[pp.menu_number-1]->selected);
			return 1;
		case FL_Enter:
		case FL_KP_Enter:
		case ' ':
			pp.state = DONE_STATE;
			return 1;
		case FL_Escape:
			setitem(0, -1, 0);
			pp.state = DONE_STATE;
			return 1;
		}
		break;
	case FL_SHORTCUT: {
		for (int mymenu = pp.nummenus; mymenu--;) {
			traymenuwindow &mw = *(pp.p[mymenu]);
			int item;
			const Fl_Menu_Item* m = mw.menu->find_shortcut(&item);
			if (m) {
				setitem(m, mymenu, item);
				if (!m->submenu()) pp.state = DONE_STATE;
				return 1;
			}
		}
	}
	break;
	case FL_MOVE:
		//printf("e=%d\n", e);
#if ! (defined(WIN32) || defined(__APPLE__))
		if (pp.state == DONE_STATE) {
			return 1; // Fix for STR #2619
		}
		/* FALLTHROUGH */
#endif
	case FL_ENTER:
	case FL_PUSH:
	case FL_DRAG: {
		int mx, my;
		Fl::get_mouse(mx, my);
		/*
		int mx = Fl::event_x_root();
		int my = Fl::event_y_root();
		*/
		int item=0;
		int mymenu = pp.nummenus-1;
		// Clicking or dragging outside menu cancels it...
		if ((!pp.menubar || mymenu) && !pp.is_inside(mx, my)) {
			setitem(0, -1, 0);
			if (e==FL_PUSH)
				pp.state = DONE_STATE;
			return 1;
		}
		for (mymenu = pp.nummenus-1; ; mymenu--) {
			item = pp.p[mymenu]->find_selected(mx, my);
			if (item >= 0)
				break;
			if (mymenu <= 0) {
				// buttons in menubars must be deselected if we move outside of them!
				if (pp.menu_number==-1 && e==FL_PUSH) {
					pp.state = DONE_STATE;
					return 1;
				}
				if (pp.current_item && pp.menu_number==0 && !pp.current_item->submenu()) {
					if (e==FL_PUSH)
						pp.state = DONE_STATE;
					setitem(0, -1, 0);
					return 1;
				}
				// all others can stay selected
				return 0;
			}
		}
		if (my == 0 && item > 0) setitem(mymenu, item - 1);
		else {
			setitem(mymenu, item);
		}
		if (e == FL_PUSH) {
			if (pp.current_item && pp.current_item->submenu() // this is a menu title
			    && item != pp.p[mymenu]->selected // and it is not already on
			    && !pp.current_item->callback_) // and it does not have a callback
				pp.state = MENU_PUSH_STATE;
			else
				pp.state = PUSH_STATE;
		}
	}
	return 1;
	case FL_RELEASE:
		// Mouse must either be held down/dragged some, or this must be
		// the second click (not the one that popped up the menu):
		if (   !Fl::event_is_click()
		       || pp.state == PUSH_STATE
		       || (pp.menubar && pp.current_item && !pp.current_item->submenu()) // button
		   ) {
				// do nothing if they try to pick inactive items
				if (!pp.current_item || pp.current_item->activevisible())
					pp.state = DONE_STATE;
		}
		return 1;
	case FL_UNFOCUS:
		//printf("e unfocus\n");
		setitem(0, -1, 0);
		pp.state = DONE_STATE;
		return 1;
	}
	return Fl_Window::handle(e);
}

const Fl_Menu_Item* Fl_TrayPopMenu::pulldown(Fl_Window *w, int X, int Y) const
{
	Fl_Group::current(0); // fix possible user error...

	int scr_x, scr_y, scr_w, scr_h;
	Fl::screen_work_area(scr_x, scr_y, scr_w, scr_h);

	traymenuwindow mw(w, menu(), X, Y, scr_x, scr_y, scr_w, scr_h);
	killfocus_ = 0;
	Fl::event_dispatch(owenevent);
	Fl::grab(mw);
	menustate pp;
	p = &pp;
	pp.p[0] = &mw;
	pp.nummenus = 1;
	pp.menubar = 0;
	pp.state = INITIAL_STATE;
	pp.current_item = 0;
	pp.menu_number = 0;
	pp.item_number = -1;

	// the main loop, runs until p.state goes to DONE_STATE:
	for (;;) {
		// make sure all the menus are shown:
		{
			for (int k = 0; k < pp.nummenus; k++) {
				if (!pp.p[k]->shown()) {
					//if (pp.p[k]->title) pp.p[k]->title->show();
					pp.p[k]->show();
#if __FLTK_WIN32__
					SetWindowPos(fl_xid(pp.p[k]), HWND_TOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE);
#endif
					killfocus_ = 0;
				}
			}
		}

		// get events:
		{
			const Fl_Menu_Item* oldi = pp.current_item;
			Fl::wait();
			//printf("msg=%x\n", fl_msg.message);
			//if ( fl_msg.message == 0xc2ba ) break;
			//if ( fl_msg.message == 0xc05d ) break;
			if (pp.state == DONE_STATE) break; // done.
			//printf("=====>focus=%d\n", killfocus_);
			if ( killfocus_ == 1 ) {
				pp.current_item = NULL;
				break;
			}
			if (pp.current_item == oldi) continue;
		}

		if (!pp.current_item) { // pointing at nothing
			// turn off selection in deepest menu, but don't erase other menus:
			pp.p[pp.nummenus-1]->set_selected(-1);
			continue;
		}		

		//pp.p[pp.menu_number]->autoscroll(pp.item_number);

		traymenuwindow& cw = *pp.p[pp.menu_number];
		const Fl_Menu_Item* m = pp.current_item;
		if (!m->activevisible()) { // pointing at inactive item
			cw.set_selected(-1);
			continue;
		}
		cw.set_selected(pp.item_number);

		if (m->submenu()) {
			const Fl_Menu_Item* menutable;
			if (m->flags & FL_SUBMENU) menutable = m+1;
			else menutable = (Fl_Menu_Item*)(m)->user_data_;
			// figure out where new menu goes:
			int nX, nY, nW, nH;
			nX = cw.x();
			nW = cw.w();
			nY = cw.y() + pp.item_number * cw.itemheight;
			nH = cw.itemheight;
			if (pp.nummenus > pp.menu_number+1 && pp.p[pp.menu_number+1]->menu == menutable) {
				// the menu is already up:
				while (pp.nummenus > pp.menu_number+2) delete pp.p[--pp.nummenus];
				pp.p[pp.nummenus-1]->set_selected(-1);
			} else {
				// delete all the old menus and create new one:
				while (pp.nummenus > pp.menu_number+1) delete pp.p[--pp.nummenus];
				pp.p[pp.nummenus++]= new traymenuwindow(w, menutable, nX, nY, nW, nH, scr_x, scr_y, scr_w, scr_h);
			}
		} else { // !m->submenu():
			while (pp.nummenus > pp.menu_number+1) delete pp.p[--pp.nummenus];
		}
	}
	const Fl_Menu_Item* m = pp.current_item;
	while (pp.nummenus>1) delete pp.p[--pp.nummenus];
	mw.hide();
	Fl::event_dispatch(NULL);
	killfocus_ = 0;
	Fl::grab(0);
	return m;
}