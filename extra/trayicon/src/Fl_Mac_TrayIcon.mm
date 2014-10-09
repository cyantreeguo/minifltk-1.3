//
// "$Id: Fl_Mac_TrayIcon.mm 10106 2014-02-19 16:02:56Z manolo $"
//
// MacOS trayicon widget for the Fast Light Tool Kit (FLTK).
//
// Copyright 1998-2013 by Bill Spitzak and others.
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

/*
 * This code has been tested on the "menubar" sample program and provides
 * basic functionality. 
 * 
 * FLTK features not supported by the Mac trayicon
 *
 * - no symbolic labels
 * - no embossed labels
 * - no font sizes
 *
 * Many other calls of the parent class don't work.
 */

#include "Fl_Platform.h"

#if __FLTK_MACOSX__

#include "Fl_Menu_Item.H"
#include "Fl_Mac_TrayIcon.H"
#include "x.H"
#include "Fl.H"

#import <Cocoa/Cocoa.h>

#ifndef NSINTEGER_DEFINED // appears with 10.5 in NSObjCRuntime.h
#if defined(__LP64__) && __LP64__
typedef long NSInteger;
typedef unsigned long NSUInteger;
#else
typedef long NSInteger;
typedef unsigned int NSUInteger;
#endif
#endif

#include "flstring.h"
#include <stdio.h>
#include <ctype.h>
#include <stdarg.h>

////////////////////////////////////////////////////////////
@interface MacStatusBar : NSObject
{
@private
	NSStatusItem* statusItem;
	NSMenu* menu;
}

@end

@implementation MacStatusBar

- (void) createMenu {
	NSZone *menuZone = [NSMenu menuZone];
	menu = [[NSMenu allocWithZone:menuZone] init];
  
	statusItem = NULL;
}

- (NSMenu*) traymenu {
	return menu;
}

- (void) show:(int)vis toToolTip:(const char*)tooltip {
    //printf("%s\n", tooltip);
    NSString *s;
    CFStringRef ss=NULL;
    if ( tooltip == NULL ) s = @"";
    else {
        ss = CFStringCreateWithCString(NULL, tooltip, kCFStringEncodingUTF8);
        s = (NSString*)ss;
    }
    //NSLog(@"nsstring=%@\n", s);
	if (vis) {
		statusItem = [[[NSStatusBar systemStatusBar]
                  statusItemWithLength:NSSquareStatusItemLength] retain];
		[statusItem setMenu:menu];
		[statusItem setHighlightMode:YES];
		[statusItem setToolTip:(NSString*)s];
	} else if (statusItem) {
		// FIXME: implement hide
		assert(!"Hide not implemented");
	}
    if ( ss != NULL ) CFRelease(ss);
}

- (void) changeIcon: (NSString*)icn {
	[statusItem setImage:[NSImage imageNamed:icn]];
}

- (void) setTooltip: (const char*)tooltip {
    NSString *s;
    CFStringRef ss=NULL;
    if ( tooltip == NULL ) s = @"";
    else {
        ss = CFStringCreateWithCString(NULL, tooltip, kCFStringEncodingUTF8);
        s = (NSString*)ss;
    }
    
    [statusItem setToolTip:s];
	
    if ( ss != NULL ) CFRelease(ss);
}

- (void) dealloc {
	if (statusItem)
		[statusItem release];
	[menu release];
	[super dealloc];
}
@end

////////////////////////////////////////////////////////////

typedef const Fl_Menu_Item *pFl_Menu_Item;

Fl_Mac_TrayIcon *fl_mac_trayicon = 0;

static char* remove_ampersand(const char *s);
extern void (*fl_lock_function)();
extern void (*fl_unlock_function)();

/*  Each MacOS trayicon contains a pointer to a record of type sys_menu_item defined below.
	The purpose of these records is to associate each MacOS system menu item with a relevant Fl_Menu_Item.
	If use_rank is YES, the "rank" field is used, and fl_mac_trayicon->menu() + rank is the address 
	of the relevant Fl_Menu_Item;
	Otherwise, the "item" field points to the relevant Fl_Menu_Item.
	This allows the MacOS system menu to use the same Fl_Menu_Item's as those used by FLTK menus, 
	the address of which can be relocated by the FLTK menu logic.
	The "item" field is used for non-relocatable Fl_Menu_Item's associated to FL_SUBMENU_POINTER.
	Sending the getFlItem message to a MacOS system menu item (of class FLTrayMenuItem) returns the address
	of the relevant Fl_Menu_Item.
*/
typedef struct {
	union {
		int rank;
		const Fl_Menu_Item *item;
	};
	BOOL use_rank;
} tray_menu_item;


@interface FLTrayMenuItem : NSMenuItem {}
- (void)doCallback: (id)unused;
- (void)directCallback: (id)unused;
- (const Fl_Menu_Item *)getFlItem;
- (void)setKeyEquivalentModifierMask: (int)value;
- (void)setFltkShortcut: (int)key;
+ (int)addNewItem: (const Fl_Menu_Item *)mitem menu: (NSMenu *)menu;
@end

@implementation FLTrayMenuItem
- (const Fl_Menu_Item *)getFlItem
// returns the Fl_Menu_Item corresponding to this system menu item
{
	tray_menu_item *smi = (tray_menu_item *)[(NSData *)[self representedObject] bytes];
	if (smi->use_rank) return fl_mac_trayicon->menu() + smi->rank;
	return smi->item;
}
- (void)doCallback: (id)unused
{
	fl_lock_function();
	const Fl_Menu_Item *item = [self getFlItem];
	fl_mac_trayicon->picked(item);
	if (item->flags & FL_MENU_TOGGLE) { // update the menu toggle symbol
		[self setState: (item->value() ? NSOnState : NSOffState)];
	} else if (item->flags & FL_MENU_RADIO) { // update the menu radio symbols
		NSMenu *menu = [self menu];
		NSInteger flRank = [menu indexOfItem: self];
		NSInteger last = [menu numberOfItems] - 1;
		int from = flRank;
		while (from > 0) {
			if ([[menu itemAtIndex: from - 1] isSeparatorItem]) break;
			item = [(FLTrayMenuItem *)[menu itemAtIndex: from - 1] getFlItem];
			if (!(item->flags & FL_MENU_RADIO)) break;
			from--;
		}
		int to = flRank;
		while (to < last) {
			if ([[menu itemAtIndex: to + 1] isSeparatorItem]) break;
			item = [(FLTrayMenuItem *)[menu itemAtIndex: to + 1] getFlItem];
			if (!(item->flags & FL_MENU_RADIO)) break;
			to++;
		}
		for (int i =  from; i <= to; i++) {
			NSMenuItem *nsitem = [menu itemAtIndex: i];
			[nsitem setState: (nsitem != self ? NSOffState : NSOnState)];
		}
	}
	fl_unlock_function();
}
- (void)directCallback: (id)unused
{
	fl_lock_function();
	Fl_Menu_Item *item = (Fl_Menu_Item *)[(NSData *)[self representedObject] bytes];
	if (item && item->callback()) item->do_callback(NULL);
	fl_unlock_function();
}
- (void)setKeyEquivalentModifierMask: (int)value
{
	NSUInteger macMod = 0;
	if (value & FL_META) macMod = NSCommandKeyMask;
	if (value & FL_SHIFT || isupper(value)) macMod |= NSShiftKeyMask;
	if (value & FL_ALT) macMod |= NSAlternateKeyMask;
	if (value & FL_CTRL) macMod |= NSControlKeyMask;
	[super setKeyEquivalentModifierMask: macMod];
}
- (void)setFltkShortcut: (int)key
{
	// Separate key and modifier
	int mod = key;
	mod &= ~FL_KEY_MASK;  // modifier(s)
	key &=  FL_KEY_MASK;  // key
	unichar mac_key = (unichar)key;
	if ((key >= (FL_F + 1)) && (key <= FL_F_Last)) { // Handle function keys
		int fkey_num = (key - FL_F);    // 1,2..
		mac_key = NSF1FunctionKey + fkey_num - 1;
	}
	[self setKeyEquivalent: [NSString stringWithCharacters: &mac_key length: 1]];
	[self setKeyEquivalentModifierMask: mod];
}
+ (int)addNewItem: (const Fl_Menu_Item *)mitem menu: (NSMenu *)menu
{
	char *name = remove_ampersand(mitem->label());
	CFStringRef cfname = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
	free(name);
	FLTrayMenuItem *item = [[FLTrayMenuItem alloc] initWithTitle: (NSString *)cfname
												  action: @selector(doCallback:)
										   keyEquivalent: @""];
	tray_menu_item smi;
	smi.rank = fl_mac_trayicon->find_index(mitem); // ≥ 0 if mitem is in the menu items of fl_mac_trayicon, -1 if not
	smi.use_rank = (smi.rank >= 0);
	if (!smi.use_rank) smi.item = mitem;
	NSData *pointer = [NSData dataWithBytes: &smi length: sizeof(smi)];
	[item setRepresentedObject: pointer];
	[menu addItem: item];
	CFRelease(cfname);
	[item setTarget: item];
	int retval = [menu indexOfItem: item];
	[item release];
	return retval;
}
@end

/*
 * Set a shortcut for an Apple menu item using the FLTK shortcut descriptor.
 */
static void setMenuShortcut(NSMenu *mh, int miCnt, const Fl_Menu_Item *m)
{
	if (!m->shortcut_) return;
	if (m->flags & FL_SUBMENU) return;
	if (m->flags & FL_SUBMENU_POINTER) return;
	FLTrayMenuItem *menuItem = (FLTrayMenuItem *)[mh itemAtIndex: miCnt];
	[menuItem setFltkShortcut: (m->shortcut_)];
}


/*
 * Set the Toggle and Radio flag based on FLTK flags
 */
static void setMenuFlags(NSMenu *mh, int miCnt, const Fl_Menu_Item *m)
{
	if (m->flags & FL_MENU_TOGGLE) {
		NSMenuItem *menuItem = [mh itemAtIndex: miCnt];
		[menuItem setState: (m->flags & FL_MENU_VALUE ? NSOnState : NSOffState)];
	} else if (m->flags & FL_MENU_RADIO) {
		NSMenuItem *menuItem = [mh itemAtIndex: miCnt];
		[menuItem setState: (m->flags & FL_MENU_VALUE ? NSOnState : NSOffState)];
	}
}

static char* remove_ampersand(const char *s)
{
	char *ret = strdup(s);
	const char *p = s;
	char *q = ret;
	while (*p != 0) {
		if (p[0] == '&') {
			if (p[1] == '&') {
				*q++ = '&'; p += 2;
			} else {
				p++;
			}
		} else {
			*q++ = *p++;
		}
	}
	*q = 0;
	return ret;
}


/*
 * create a sub menu for a specific menu handle
 */
static void createSubMenu(NSMenu *mh, pFl_Menu_Item &mm,  const Fl_Menu_Item *mitem)
{
	NSMenu *submenu;
	int miCnt, flags;

	NSMenuItem *menuItem;
	char *ts = remove_ampersand(mitem->text);
	CFStringRef title = CFStringCreateWithCString(NULL, ts, kCFStringEncodingUTF8);
	free(ts);
	submenu = [[NSMenu alloc] initWithTitle: (NSString *)title];
	CFRelease(title);
	[submenu setAutoenablesItems: NO];

	int cnt;
	cnt = [mh numberOfItems];
	cnt--;
	menuItem = [mh itemAtIndex: cnt];
	[menuItem setSubmenu: submenu];
	[submenu release];

	while (mm->text) {
		if (!mm->visible()) { // skip invisible items and submenus
			mm = mm->next(0);
			continue;
		}
		miCnt = [FLTrayMenuItem addNewItem: mm menu: submenu];
		setMenuFlags(submenu, miCnt, mm);
		setMenuShortcut(submenu, miCnt, mm);
		if (mm->flags & FL_MENU_INACTIVE || mitem->flags & FL_MENU_INACTIVE) {
			NSMenuItem *item = [submenu itemAtIndex: miCnt];
			[item setEnabled: NO];
		}
		flags = mm->flags;
		if (mm->flags & FL_SUBMENU) {
			mm++;
			createSubMenu(submenu, mm, mm - 1);
		} else if (mm->flags & FL_SUBMENU_POINTER) {
			const Fl_Menu_Item *smm = (Fl_Menu_Item *)mm->user_data_;
			createSubMenu(submenu, smm, mm);
		}
		if (flags & FL_MENU_DIVIDER) {
			[submenu addItem: [NSMenuItem separatorItem]];
		}
		mm++;
	}
}


/*
 * convert a complete Fl_Menu_Item array into a series of menus in the top menu bar
 * ALL PREVIOUS SYSTEM MENUS, EXCEPT THE APPLICATION MENU, ARE REPLACED BY THE NEW DATA
 */
void Fl_Mac_TrayIcon::convertToMenuBar(const Fl_Menu_Item *mm, const char* tooltip)
{
	NSMenu *fl_system_menu = [macStatusBar traymenu];
	int rank;
	int count; //first, delete all existing system menus
	count = [fl_system_menu numberOfItems];
	for (int i = count - 1; i > 0; i--) {
		[fl_system_menu removeItem: [fl_system_menu itemAtIndex: i]];
	}
	//now convert FLTK stuff into MacOS menus
	for (;;) {
		if (!mm || !mm->text) break;
		if (!mm->visible()) { // skip invisible menus
			mm = mm->next(0);
			continue;
		}
		rank = [FLTrayMenuItem  addNewItem: mm menu: fl_system_menu];

		if (mm->flags & FL_SUBMENU) {
			mm++;
			createSubMenu(fl_system_menu, mm, mm - 1);
		} else if (mm->flags & FL_SUBMENU_POINTER) {
			const Fl_Menu_Item *smm = (Fl_Menu_Item *)mm->user_data_;
			createSubMenu(fl_system_menu, smm, mm);
		}
		mm++;
	}
	
	isVisible = true;
	[macStatusBar show:1 toToolTip:tooltip];
	setActiveIcon(activeIcon);
}


/**
 * @brief create a system menu bar using the given list of menu structs
 *
 * \author Matthias Melcher
 *
 * @param m list of Fl_Menu_Item
 */
void Fl_Mac_TrayIcon::menu(const Fl_Menu_Item *m)
{
	fl_open_display();
	Fl_Menu_Bar::menu(m);
}


/**
 * @brief add to the system menu bar a new menu item
 *
 * add to the system menu bar a new menu item, with a title string, shortcut int,
 * callback, argument to the callback, and flags.
 *
 * @see Fl_Menu_::add(const char* label, int shortcut, Fl_Callback *cb, void *user_data, int flags) 
 */
int Fl_Mac_TrayIcon::add(const char *label, int shortcut, Fl_Callback *cb, void *user_data, int flags)
{
	fl_open_display();
	int rank = Fl_Menu_::add(label, shortcut, cb, user_data, flags);
	return rank;
}

/**
 * Forms-compatible procedure to add items to the system menu bar
*
 * @see Fl_Menu_::add(const char* str) 
 */
int Fl_Mac_TrayIcon::add(const char *str)
{
	fl_open_display();
	int rank = Fl_Menu_::add(str);
	return rank;
}

/**
 * @brief insert in the system menu bar a new menu item
 *
 * insert in the system menu bar a new menu item, with a title string, shortcut int,
 * callback, argument to the callback, and flags.
 *
 * @see Fl_Menu_::insert(int index, const char* label, int shortcut, Fl_Callback *cb, void *user_data, int flags) 
 */
int Fl_Mac_TrayIcon::insert(int index, const char *label, int shortcut, Fl_Callback *cb, void *user_data, int flags)
{
	fl_open_display();
	int rank = Fl_Menu_::insert(index, label, shortcut, cb, user_data, flags);
	return rank;
}

void Fl_Mac_TrayIcon::clear()
{
	Fl_Menu_::clear();
	convertToMenuBar(NULL, NULL);
}

int Fl_Mac_TrayIcon::clear_submenu(int index)
{
	int retval = Fl_Menu_::clear_submenu(index);
	return retval;
}

/**
 * @brief remove an item from the system menu bar
 *
 * @param rank		the rank of the item to remove
 */
void Fl_Mac_TrayIcon::remove(int rank)
{
	Fl_Menu_::remove(rank);
}

/**
 * @brief rename an item from the system menu bar
 *
 * @param rank		the rank of the item to rename
 * @param name		the new item name as a UTF8 string
 */
void Fl_Mac_TrayIcon::replace(int rank, const char *name)
{
	Fl_Menu_::replace(rank, name);
}

/** Show the system menu after any change to its items.
 */
void Fl_Mac_TrayIcon::show(const char *tooltip)
{
	convertToMenuBar(Fl_Menu_::menu(), tooltip);
}

static int process_trayicon_shortcuts(int event)
{
	if (event != FL_SHORTCUT || !fl_mac_trayicon || Fl::modal()) return 0;
	// is the last event the shortcut of an item of the fl_mac_trayicon menu ?
	const Fl_Menu_Item *item = fl_mac_trayicon->menu()->test_shortcut();
	if (!item) return 0;
	if (item->visible()) // have the system menu process the shortcut, highlighting the corresponding menu
		[[NSApp mainMenu] performKeyEquivalent: [NSApp currentEvent]];
	else // have FLTK process the shortcut associated to an invisible Fl_Menu_Item
		fl_mac_trayicon->picked(item);
	return 1;
}


/**
 The constructor.
 On Mac OS X, all arguments are unused. On other platforms they are used as by Fl_Menu_Bar::Fl_Menu_Bar().
 */
Fl_Mac_TrayIcon::Fl_Mac_TrayIcon(int x, int y, int w, int h, const char *l) : Fl_Menu_Bar(x, y, w, h, l)
{
	icons = NULL;
	numIcons = 0;
	activeIcon = 0;
	isVisible = false;
	
	deactivate();         // don't let the old area take events
	fl_mac_trayicon = this;
	//Fl::add_handler(process_trayicon_shortcuts);
	
	macStatusBar = [[MacStatusBar alloc] init];
	[macStatusBar createMenu];
}

/** The destructor */
Fl_Mac_TrayIcon::~Fl_Mac_TrayIcon()
{
	fl_mac_trayicon = 0;
	clear();
	//Fl::remove_handler(process_trayicon_shortcuts);
	
	[macStatusBar release];
}

int Fl_Mac_TrayIcon::addIcon(void* icon)
{
	char** newicons;
	newicons = new char*[numIcons+1];
	if (!newicons)
		return -1;
	newicons[numIcons] = new char[strlen((char*)icon)+1];
	if (!newicons[numIcons]) {
		delete[] newicons;
		return -1;
	}
	strcpy(newicons[numIcons], (char*)icon);
	for (int i = 0; i < numIcons; ++i)
		newicons[i] = icons[i];
	delete[] icons;
	icons = newicons;
	++numIcons;
	return 0;
}

int Fl_Mac_TrayIcon::setActiveIcon(int iconId)
{
	if (iconId < 0 || iconId >= numIcons)
		return -1;
	activeIcon = iconId;
	if (isVisible) {
		NSString* istr = [NSString stringWithUTF8String:icons[iconId]];
		[macStatusBar changeIcon:istr]; 
		[istr release];
	}
	return 0;
}

void Fl_Mac_TrayIcon::changetooltip(const char *s)
{
    [macStatusBar setTooltip:s];
}

void Fl_Mac_TrayIcon::WinHide(Fl_Window *w)
{
    [fl_xid(w) orderOut: nil];
}

void Fl_Mac_TrayIcon::WinShow(Fl_Window *w)
{
    [fl_xid(w) makeKeyAndOrderFront: nil];
}

#endif /* __APPLE__ */

//
// End of "$Id: Fl_Mac_TrayIcon.mm 10106 2014-02-19 16:02:56Z manolo $".
//
