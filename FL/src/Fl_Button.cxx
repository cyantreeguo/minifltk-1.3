//
// "$Id: Fl_Button.cxx 9855 2013-03-29 18:26:36Z greg.ercolano $"
//
// Button widget for the Fast Light Tool Kit (FLTK).
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
#include "Fl_Button.H"
#include "Fl_Group.H"
#include "Fl_Window.H"

#include "Fl_Radio_Button.H"
#include "Fl_Toggle_Button.H"


Fl_Widget_Tracker *Fl_Button::key_release_tracker = 0;


// There are a lot of subclasses, named Fl_*_Button.  Some of
// them are implemented by setting the type() value and testing it
// here.  This includes Fl_Radio_Button and Fl_Toggle_Button

/**
  Sets the current value of the button.
  A non-zero value sets the button to 1 (ON), and zero sets it to 0 (OFF).
  \param[in] v button value.
  \see set(), clear()
 */
int Fl_Button::value(int v)
{
	v = v ? 1 : 0;
	oldval = v;
	clear_changed();
	if (value_ != v) {
		value_ = v;
		if (box()) redraw();
		else redraw_label();
		return 1;
	} else {
		return 0;
	}
}

/**
  Turns on this button and turns off all other radio buttons in the group
  (calling \c value(1) or \c set() does not do this).
 */
void Fl_Button::setonly()   // set this radio button on, turn others off
{
	value(1);
	Fl_Group* g = parent();
	Fl_Widget*const* a = g->array();
	for (int i = g->children(); i--;) {
		Fl_Widget* o = *a++;
		if (o != this && o->type()==FL_RADIO_BUTTON) ((Fl_Button*)o)->value(0);
	}
}

void Fl_Button::draw()
{
	if (type() == FL_HIDDEN_BUTTON) return;
	Fl_Color col = value() ? selection_color() : color();
	draw_box(value() ? (down_box()?down_box():fl_down(box())) : box(), col);
	draw_backdrop();
	if (labeltype() == FL_NORMAL_LABEL && value()) {
		Fl_Color c = labelcolor();
		labelcolor(fl_contrast(c, col));
		draw_label();
		labelcolor(c);
	} else draw_label();
	if (Fl::focus() == this) draw_focus();
}

int Fl_Button::handle(int event)
{
	int newval;
	switch (event) {
	case FL_ENTER: /* FALLTHROUGH */
	case FL_LEAVE:
//  if ((value_?selection_color():color())==FL_GRAY) redraw();
		return 1;
	case FL_PUSH:
		if (Fl::visible_focus() && handle(FL_FOCUS)) Fl::focus(this);
		/* FALLTHROUGH */
	case FL_DRAG:
		if (Fl::event_inside(this)) {
			if (type() == FL_RADIO_BUTTON) newval = 1;
			else newval = !oldval;
		} else {
			clear_changed();
			newval = oldval;
		}
		if (newval != value_) {
			value_ = newval;
			set_changed();
			redraw();
			if (when() & FL_WHEN_CHANGED) do_callback();
		}
		return 1;
	case FL_RELEASE:
		if (value_ == oldval) {
			if (when() & FL_WHEN_NOT_CHANGED) do_callback();
			return 1;
		}
		set_changed();
		if (type() == FL_RADIO_BUTTON) setonly();
		else if (type() == FL_TOGGLE_BUTTON) oldval = value_;
		else {
			value(oldval);
			set_changed();
			if (when() & FL_WHEN_CHANGED) {
				Fl_Widget_Tracker wp(this);
				do_callback();
				if (wp.deleted()) return 1;
			}
		}
		if (when() & FL_WHEN_RELEASE) do_callback();
		return 1;
	case FL_SHORTCUT:
		if (!(shortcut() ?
		      Fl::test_shortcut(shortcut()) : test_shortcut())) return 0;
		if (Fl::visible_focus() && handle(FL_FOCUS)) Fl::focus(this);
		goto triggered_by_keyboard;
	case FL_FOCUS :
	case FL_UNFOCUS :
		if (Fl::visible_focus()) {
			if (box() == FL_NO_BOX) {
				// Widgets with the FL_NO_BOX boxtype need a parent to
				// redraw, since it is responsible for redrawing the
				// background...
				int X = x() > 0 ? x() - 1 : 0;
				int Y = y() > 0 ? y() - 1 : 0;
				if (window()) window()->damage(FL_DAMAGE_ALL, X, Y, w() + 2, h() + 2);
			} else redraw();
			return 1;
		} else return 0;
		/* NOTREACHED */
	case FL_KEYBOARD :
		if (Fl::focus() == this && Fl::event_key() == ' ' &&
		    !(Fl::event_state() & (FL_SHIFT | FL_CTRL | FL_ALT | FL_META))) {
			set_changed();
triggered_by_keyboard:
			Fl_Widget_Tracker wp(this);
			if (type() == FL_RADIO_BUTTON) {
				if (!value_) {
					setonly();
					if (when() & FL_WHEN_CHANGED) do_callback();
				}
			} else if (type() == FL_TOGGLE_BUTTON) {
				value(!value());
				if (when() & FL_WHEN_CHANGED) do_callback();
			} else {
				simulate_key_action();
			}
			if (wp.deleted()) return 1;
			if (when() & FL_WHEN_RELEASE) do_callback();
			return 1;
		}
	default:
		return 0;
	}
}

void Fl_Button::simulate_key_action()
{
	if (key_release_tracker) {
		Fl::remove_timeout(key_release_timeout, key_release_tracker);
		key_release_timeout(key_release_tracker);
	}
	value(1);
	redraw();
	key_release_tracker = new Fl_Widget_Tracker(this);
	Fl::add_timeout(0.15, key_release_timeout, key_release_tracker);
}

void Fl_Button::key_release_timeout(void *d)
{
	Fl_Widget_Tracker *wt = (Fl_Widget_Tracker*)d;
	if (!wt)
		return;
	if (wt==key_release_tracker)
		key_release_tracker = 0L;
	Fl_Button *btn = (Fl_Button*)wt->widget();
	if (btn) {
		btn->value(0);
		btn->redraw();
	}
	delete wt;
}

/**
  The constructor creates the button using the given position, size and label.
  \param[in] X, Y, W, H position and size of the widget
  \param[in] L widget label, default is no label
 */
Fl_Button::Fl_Button(int X, int Y, int W, int H, const char *L)
	: Fl_Widget(X,Y,W,H,L)
{
	box(FL_UP_BOX);
	down_box(FL_NO_BOX);
	value_ = oldval = 0;
	shortcut_ = 0;
	set_flag(SHORTCUT_LABEL);
}


//
// End of "$Id: Fl_Button.cxx 9855 2013-03-29 18:26:36Z greg.ercolano $".
//