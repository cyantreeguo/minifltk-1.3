#ifndef _Fl_Linux_TrayIcon_H_
#define _Fl_Linux_TrayIcon_H_

#include "Fl_Platform.h"
#if __FLTK_LINUX__

#include <stdio.h>
#include <stdlib.h>
#include "Fl.H"
#include "Fl_Window.H"
#include "Fl_Image.H"
#include "x.H"

#include <X11/Xlib.h>
#include <X11/Xutil.h>

class Fl_Linux_TrayIcon {
public:
	enum TrayMouseType {
		tmt_LBUTTONDOWN,
		tmt_LBUTTONUP,
		tmt_LBUTTONDBLCLK,

		tmt_RBUTTONUP,
		tmt_RBUTTONDBLCLK,
		tmt_RBUTTONDOWN,

		tmt_MBUTTONDOWN,
		tmt_MBUTTONUP,
		tmt_MBUTTONDBLCLK,

		tmt_MOUSEHOVER,
		tmt_MOUSELEAVE,
	};

public:
	Fl_Linux_TrayIcon(Fl_Window *win, void cb(TrayMouseType tmt, void *x)=0, void *x=0, unsigned char ActiveMouseHover=0);

	~Fl_Linux_TrayIcon()
	{
		Delete();
	}

public:
	unsigned char Create(char *Tooltip, Fl_Image *img)
	{
		if ( img == NULL ) return 0;
		Delete();
		CreateTrayWin(Tooltip, img);
		return DockIcon();
	}

	unsigned char Create(char *Tooltip, Fl_Image** imgs, int imgnum, unsigned long delay)
	{
	    if ( imgs == NULL ) return 0;
	    if ( 0 == Create(Tooltip, imgs[0]) ) return 0;
		//Start the animation
		StartAnimation(imgs, imgnum, delay);
	    return 1;
	}

	void Delete()
	{
		if ( traywin_ != NULL ) {
			delete traywin_;
			traywin_ = NULL;
		}

		int i;
		if ( imgnum_ > 0 ) {
		    for (i=0; i<imgnum_; i++) {
		        if (imgs_[i].img != NULL) delete imgs_[i].img;
		    }
		    free(imgs_);
		}
		imgnum_ = 0;
	}

	//Sets or gets the Tooltip text
	unsigned char SetTooltipText(char *Tooltip)
	{
		if ( Tooltip == NULL ) return 0;
		if ( traywin_ == NULL ) return 0;

		traywin_->copy_tooltip(Tooltip);

		return 1;
	}

	//Sets or gets the icon displayed
	unsigned char SetIcon(Fl_Image *img);
	unsigned char UsingAnimatedIcon() const
	{
	    return (imgnum_ != 0);
	}

	void ActiveMouseHover(unsigned char active);

protected:
	void CreateTrayWin(char *Tooltip, Fl_Image *img);
	unsigned char DockIcon();

	void StartAnimation(Fl_Image** imgs, int imgnum, unsigned long delay)
	{
	    if (imgnum < 2) return; //must be using at least 2 icons if you are using animation
        if (imgs == NULL ) return;        //array of icon handles must be valid
        if ( delay < 1 ) return;        //must be non zero timer interval

        //Stop the animation if already started
        StopAnimation();

        //Hive away all the values locally
        imgnum_ = imgnum;
        imgs_ = (IMGSTRUCT *)malloc(imgnum_ * sizeof(IMGSTRUCT));
        int i;
        for (i=0; i<imgnum_; i++) {
            imgs_[i].img = NULL;
            if ( imgs[i] != NULL ) imgs_[i].img = imgs[i]->copy();
        }

        m_dwDelay = delay;

        //Start up the timer
        m_timeruning = 1;
        Fl::add_timeout(double(delay) / 1000.0, cb_time, this);
	}
	void StopAnimation()
	{
	    //Kill the timer
        if ( m_timeruning ) {
            Fl::remove_timeout(cb_time, this);
            m_timeruning = 0;
        }

        //Free up the memory
        int i;
		if ( imgnum_ > 0 ) {
		    for (i=0; i<imgnum_; i++) {
		        if (imgs_[i].img != NULL) delete imgs_[i].img;
		    }
		    free(imgs_);
		}
		imgnum_ = 0;

        //Reset the other animation related variables
        m_nCurrentIconIndex = 0;
    }
	static void cb_time(void *x)
	{
		Fl_Linux_TrayIcon *o = (Fl_Linux_TrayIcon *)x;
		if ( !o ) return;
		o->cb_time_i();
	}
	void cb_time_i()
	{
	    //increment the icon index
        ++m_nCurrentIconIndex;
        m_nCurrentIconIndex = m_nCurrentIconIndex % imgnum_;

        //update the tray icon
        SetIcon(imgs_[m_nCurrentIconIndex].img);

        Fl::add_timeout(double(m_dwDelay) / 1000.0, cb_time, this);
	}

private:
	Fl_Window *win_;
	Window window_;
	Fl_Window *traywin_;
	Window traywindow_;
	Window managerWin_;

	unsigned char m_timeruning;
	typedef struct {
        Fl_Image *img;
	}IMGSTRUCT;
	IMGSTRUCT *imgs_;
	int imgnum_;
	int m_nCurrentIconIndex, m_dwDelay;

private:
	struct {
		void (*callback)(TrayMouseType tmt, void *x);
		void *x;
	} m_cb;
	void callback(TrayMouseType tmt)
	{
		if ( m_cb.callback == 0 ) return;
		m_cb.callback(tmt, m_cb.x);
	}

	unsigned char activemousehover_;

protected:
    static void cb_iconwindow(TrayMouseType tmt, void *x)
    {
        Fl_Linux_TrayIcon *o = (Fl_Linux_TrayIcon *)x;
        o->callback(tmt);
    }
};

#endif // #if __FLTK_LINUX__

#endif // #ifndef _Fl_Linux_TrayIcon_H_
