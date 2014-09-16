#ifndef Fl_MAC_TRAYICON_H
#define Fl_MAC_TRAYICON_H

#include "Fl_Platform.h"

#if __FLTK_MACOSX__

#include "Fl_Menu_Bar.H"
#include "x.H"

typedef struct objc_object *id;

class Fl_Mac_TrayIcon : public Fl_Menu_Bar
{
protected:
	void draw() {}
	void convertToMenuBar(const Fl_Menu_Item *mm, const char *tooltip);
public:
	Fl_Mac_TrayIcon(int x,int y,int w,int h,const char *l=0);
	~Fl_Mac_TrayIcon();

	int addIcon(void* icon);
	int setActiveIcon(int iconId);

	/** Return the trayicon menu's array of Fl_Menu_Item's
	 */
	const Fl_Menu_Item *menu() const {
		return Fl_Menu_::menu();
	}
	void menu(const Fl_Menu_Item *m);
	int add(const char* label, int shortcut, Fl_Callback*, void *user_data=0, int flags=0);
	/** Adds a new menu item.
	 \see Fl_Menu_::add(const char* label, int shortcut, Fl_Callback*, void *user_data=0, int flags=0)
	 */
	int add(const char* label, const char* shortcut, Fl_Callback* cb, void *user_data=0, int flags=0) {
		return add(label, fl_old_shortcut(shortcut), cb, user_data, flags);
	}
	int add(const char* str);
	int insert(int index, const char* label, int shortcut, Fl_Callback *cb, void *user_data=0, int flags=0);
	/** Insert a new menu item.
	 \see Fl_Menu_::insert(int index, const char* label, const char* shortcut, Fl_Callback *cb, void *user_data=0, int flags=0)
	 */
	int insert(int index, const char* label, const char* shortcut, Fl_Callback *cb, void *user_data=0, int flags=0) {
		return insert(index, label, fl_old_shortcut(shortcut), cb, user_data, flags);
	}
	void remove(int n);
	void replace(int rank, const char *name);
	/** Set the Fl_Menu_Item array pointer to null, indicating a zero-length menu.
	 \see Fl_Menu_::clear()
	 */
	void clear();
	/** Clears the specified submenu pointed to by index of all menu items.
	 \see Fl_Menu_::clear_submenu(int index)
	 */
	int clear_submenu(int index);
	/** Make the shortcuts for this menu work no matter what window has the focus when you type it.
	 */
	void global() {};
	/** Sets the flags of item i
	 \see Fl_Menu_::mode(int i, int fl) */
	void 	mode (int i, int fl) {
		Fl_Menu_::mode(i, fl);
	}
	/** Gets the flags of item i.
	 */
	int mode(int i) const {
		return Fl_Menu_::mode(i);
	}
	/** Changes the shortcut of item i to n.
	 */
	void shortcut (int i, int s) {
		Fl_Menu_::shortcut(i, s);
	};

	void show(const char *tooltip=NULL);
    
    void changetooltip(const char *s);
    
    void WinHide(Fl_Window *w);
    void WinShow(Fl_Window *w);

private:
	id macStatusBar;
	char** icons;
	unsigned int numIcons;
	unsigned int activeIcon;
	bool isVisible;
};

#endif // __FLTK_MACOSX__

#endif // Fl_MAC_TRAYICON_H
