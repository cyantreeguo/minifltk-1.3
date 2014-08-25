#ifndef _Fl_Win32_TrayIcon_H_
#define _Fl_Win32_TrayIcon_H_

#include "Fl_Platform.h"
#if __FLTK_WIN32__

#include <stdio.h>
#include <Windows.h>
#include "ShellApi.h"
#include "Fl.H"

class Fl_Win32_TrayIcon {
public:
	enum TrayMouseType {
		tmt_MBUTTONDOWN,
		tmt_RBUTTONDOWN,
		tmt_LBUTTONDOWN,
		tmt_LBUTTONUP,
		tmt_LBUTTONDBLCLK,
		tmt_RBUTTONUP,
		tmt_RBUTTONDBLCLK,
		tmt_MBUTTONUP,
		tmt_MBUTTONDBLCLK,
		tmt_MOUSEHOVER,
		tmt_MOUSELEAVE,
	};

	enum BalloonStyle {
		bsWarning,
		bsError,
		bsInfo,
		bsNone,
		bsUser
	};

public:
	Fl_Win32_TrayIcon(HWND hWnd, void cb(TrayMouseType tmt, void *x)=0, void *x=0, BOOL ActiveMouseHover=FALSE, DWORD dwDelay=1500);
	~Fl_Win32_TrayIcon();

public:
	BOOL Create(char *Tooltip, HICON hIcon, BOOL bShow=TRUE);
	BOOL Create(char *Tooltip, HICON* phIcons, int nNumIcons, DWORD dwDelay, BOOL bShow = TRUE);
	BOOL Create(char *Tooltip, char *BalloonText, char *BalloonCaption, UINT nTimeout, BalloonStyle style, HICON hIcon, BOOL bNoSound = FALSE, 
		BOOL bLargeIcon = FALSE, BOOL bRealtime = FALSE, HICON hBalloonIcon = NULL, BOOL bQuietTime = FALSE, BOOL bShow = TRUE);
	BOOL Create(char *Tooltip, char *BalloonText, char *BalloonCaption, UINT nTimeout, BalloonStyle style, HICON* phIcons, int nNumIcons, DWORD dwDelay, 
		BOOL bNoSound = FALSE, BOOL bLargeIcon = FALSE, BOOL bRealtime = FALSE, HICON hBalloonIcon = NULL, BOOL bQuietTime = FALSE, BOOL bShow = TRUE);

	//Sets or gets the Tooltip text
	BOOL SetTooltipText(char *Tooltip);
	int	GetTooltipMaxSize();

	//Sets or gets the icon displayed
	BOOL SetIcon(HICON hIcon);
	BOOL SetIcon(LPCTSTR lpIconName);
	BOOL SetIcon(UINT nIDResource);
	BOOL SetIcon(HICON* phIcons, int nNumIcons, DWORD dwDelay);
	BOOL UsingAnimatedIcon() const;

	//Modification of the tray icons
	void Delete();
	BOOL Create(BOOL bShow = TRUE);
	BOOL IconShow();
	BOOL IconHide();

	//Status information
	BOOL IsShowing() const { return !IsHidden(); };
	BOOL IsHidden() const { return m_bHidden; };

	//Sets or gets the Balloon style tooltip settings
	BOOL SetBalloonDetails(char *BalloonText, char *BalloonCaption, BalloonStyle style, UINT nTimeout, HICON hUserIcon = NULL, BOOL bNoSound = FALSE, 
		BOOL bLargeIcon = FALSE, BOOL bRealtime = FALSE, HICON hBalloonIcon = NULL);
	UINT GetBalloonTimeout() const;

	//Other functionality
	BOOL SetVersion(UINT uVersion);
	BOOL SetFocus();

	BOOL WinIsShow();
	void WinShow();
	void WinHide();
	void WinShowTaskbar();
	void WinHideTaskbar();

	//Helper functions to load tray icon from resources
	static HICON LoadIcon(LPCTSTR lpIconName, BOOL bLargeIcon = FALSE);
	static HICON LoadIcon(UINT nIDResource, BOOL bLargeIcon = FALSE);
	static HICON LoadIcon(HINSTANCE hInstance, LPCTSTR lpIconName, BOOL bLargeIcon = FALSE);
	static HICON LoadIcon(HINSTANCE hInstance, UINT nIDResource, BOOL bLargeIcon = FALSE);

	void MouseHover(BOOL v, DWORD dwDelay) 
	{
		m_MouseHoverDelay = dwDelay;
		if ( v == m_ActiveMouseHover ) return;
		m_ActiveMouseHover = v;

		m_MouseHover = FALSE;
		if ( m_ActiveMouseHover ) {
			Fl::add_timeout(double(m_MouseHoverDelay) / 1000.0, cb_time_hover, this);
		} else {
			Fl::remove_timeout(cb_time_hover, this);
		}
	}

protected:
	DWORD GetNOTIFYICONDATASizeForOS();
	wchar_t *u2wc(char *s);

	void StartAnimation(HICON* phIcons, int nNumIcons, DWORD dwDelay);
	void StopAnimation();
	static void cb_time(void *x)
	{
		Fl_Win32_TrayIcon *o = (Fl_Win32_TrayIcon *)x;
		if ( !o ) return;
		o->cb_time_i();
	}
	void cb_time_i();

	static int msg_handler(int msg);
	int msg_handler_i(int msg);

private:
	HWND hwnd_;

	enum ShellVersion {
		Version4     = 0, //PreWin2k
		Version5     = 1, //Win2k
		Version6     = 2, //XP
		VersionVista = 3, //Vista
		Version7     = 4, //Windows7
	};
	ShellVersion     m_ShellVersion;

	typedef struct _NOTIFYICONDATA_1 { //The version of the structure supported by Shell v4
		DWORD cbSize;
		HWND hWnd;
		UINT uID;
		UINT uFlags;
		UINT uCallbackMessage;
		HICON hIcon;
		wchar_t szTip[64];
	} NOTIFYICONDATA_1;

	typedef struct _NOTIFYICONDATA_2 { //The version of the structure supported by Shell v5
		DWORD cbSize;
		HWND hWnd;
		UINT uID;
		UINT uFlags;
		UINT uCallbackMessage;
		HICON hIcon;
		wchar_t szTip[128];
		DWORD dwState;
		DWORD dwStateMask;
		wchar_t szInfo[256];
		union {
			UINT uTimeout;
			UINT uVersion;
		} DUMMYUNIONNAME;
		wchar_t szInfoTitle[64];
		DWORD dwInfoFlags;
	} NOTIFYICONDATA_2;

	typedef struct _NOTIFYICONDATA_3 { //The version of the structure supported by Shell v6
		DWORD cbSize;
		HWND hWnd;
		UINT uID;
		UINT uFlags;
		UINT uCallbackMessage;
		HICON hIcon;
		wchar_t szTip[128];
		DWORD dwState;
		DWORD dwStateMask;
		wchar_t szInfo[256];
		union {
			UINT uTimeout;
			UINT uVersion;
		} DUMMYUNIONNAME;
		wchar_t szInfoTitle[64];
		DWORD dwInfoFlags;
		GUID guidItem;
	} NOTIFYICONDATA_3;

	typedef struct _NOTIFYICONDATA_4 { //The version of the structure supported by Shell v7
		DWORD cbSize;
		HWND hWnd;
		UINT uID;
		UINT uFlags;
		UINT uCallbackMessage;
		HICON hIcon;
		wchar_t szTip[128];
		DWORD dwState;
		DWORD dwStateMask;
		wchar_t szInfo[256];
		union {
			UINT uTimeout;
			UINT uVersion;
		} DUMMYUNIONNAME;
		wchar_t szInfoTitle[64];
		DWORD dwInfoFlags;
		GUID guidItem;
		HICON hBalloonIcon;
	} NOTIFYICONDATA_4;
	NOTIFYICONDATA_4 m_NotifyIconData;

	BOOL m_bCreated;
	BOOL m_bHidden;
	HICON* m_phIcons;
	int m_nNumIcons;
	int m_nCurrentIconIndex;
	DWORD m_dwDelay;
	BOOL m_timeruning;
	int m_nTooltipMaxSize;

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

	BOOL m_ActiveMouseHover;
	DWORD m_MouseHoverDelay;
	BOOL m_MouseHover;
	static void cb_time_hover(void *x)
	{
		Fl_Win32_TrayIcon *o = (Fl_Win32_TrayIcon *)x;
		if ( !o ) return;
		o->cb_time_hover_i();
	}
	void cb_time_hover_i();
	int m_Hover_x, m_Hover_y;
};

#endif // #if __FLTK_WIN32__

#endif // #ifndef _Fl_Win32_TrayIcon_H_
