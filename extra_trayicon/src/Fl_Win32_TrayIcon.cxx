#include "../Fl_Win32_TrayIcon.h"

#if __FLTK_WIN32__

#include "x.H"
#include "fl_utf8.h"
#include "shlwapi.h"

//Defines our own versions of various constants we use from ShellApi.h. This allows us to operate in a mode
//where we do not depend on the value set for _WIN32_IE
#ifndef NIIF_USER
#define NIIF_USER 0x00000004
#endif

#ifndef NIF_STATE
#define NIF_STATE 0x00000008
#endif

#ifndef NIF_INFO
#define NIF_INFO 0x00000010
#endif

#ifndef NIF_REALTIME
#define NIF_REALTIME 0x00000040
#endif

#ifndef NIS_HIDDEN
#define NIS_HIDDEN 0x00000001
#endif

#ifndef NOTIFYICON_VERSION
#define NOTIFYICON_VERSION 3
#endif

#ifndef NIM_SETVERSION
#define NIM_SETVERSION 0x00000004
#endif

#ifndef NIIF_NONE
#define NIIF_NONE 0x00000000
#endif

#ifndef NIIF_INFO
#define NIIF_INFO 0x00000001
#endif

#ifndef NIIF_WARNING
#define NIIF_WARNING 0x00000002
#endif

#ifndef NIIF_ERROR
#define NIIF_ERROR 0x00000003
#endif

#ifndef NIIF_USER
#define NIIF_USER 0x00000004
#endif

#ifndef NIIF_NOSOUND
#define NIIF_NOSOUND 0x00000010
#endif

#ifndef NIM_SETFOCUS
#define NIM_SETFOCUS 0x00000003
#endif

#ifndef NIIF_LARGE_ICON
#define NIIF_LARGE_ICON 0x00000020
#endif

#ifndef NIIF_RESPECT_QUIET_TIME
#define NIIF_RESPECT_QUIET_TIME 0x00000080
#endif


///////////////////////////////// Implementation //////////////////////////////

const UINT wm_TaskbarCreated = RegisterWindowMessage("Fl_Win32_TrayIcon_Created");

Fl_Win32_TrayIcon::Fl_Win32_TrayIcon(HWND hWnd, void cb(TrayMouseType tmt, void *x), void *x, BOOL ActiveMouseHover, DWORD dwDelay)
{
	typedef HRESULT (CALLBACK DLLGETVERSION)(DLLVERSIONINFO*);
	typedef DLLGETVERSION* LPDLLGETVERSION;

	m_bCreated = FALSE;
	m_bHidden = FALSE;
	m_ShellVersion = Version4; //Assume version 4 of the shell
	m_phIcons = NULL;
	m_nNumIcons = 0;
	m_nCurrentIconIndex = 0;
	m_timeruning = FALSE;
	m_nTooltipMaxSize = -1;
	hwnd_ = hWnd;

	//Try to get the details with DllGetVersion
	HMODULE hShell32 = GetModuleHandle("SHELL32.DLL");
	if (hShell32) {
		LPDLLGETVERSION lpfnDllGetVersion = (LPDLLGETVERSION)(GetProcAddress(hShell32, "DllGetVersion"));
		if (lpfnDllGetVersion) {
			DLLVERSIONINFO vinfo;
			vinfo.cbSize = sizeof(DLLVERSIONINFO);
			if (SUCCEEDED(lpfnDllGetVersion(&vinfo))) {
				if (vinfo.dwMajorVersion > 6 || (vinfo.dwMajorVersion == 6 && vinfo.dwMinorVersion > 0))
					m_ShellVersion = Version7;
				else if (vinfo.dwMajorVersion == 6) {
					if (vinfo.dwBuildNumber >= 6000)
						m_ShellVersion = VersionVista;
					else
						m_ShellVersion = Version6;
				} else if (vinfo.dwMajorVersion >= 5)
					m_ShellVersion = Version5;
			}
		}
	}

	memset(&m_NotifyIconData, 0, sizeof(m_NotifyIconData));
	m_NotifyIconData.cbSize = GetNOTIFYICONDATASizeForOS();

	Fl::add_handler(msg_handler);

	m_Hover_x = 0; m_Hover_y = 0;
	m_MouseHover = FALSE;
	m_ActiveMouseHover = ActiveMouseHover;
	m_MouseHoverDelay = dwDelay;
	if ( m_ActiveMouseHover ) {
		Fl::add_timeout(double(m_MouseHoverDelay) / 1000.0, cb_time_hover, this);
	}

	m_cb.callback = cb;
	m_cb.x = x;
}

void Fl_Win32_TrayIcon::cb_time_hover_i()
{
	POINT ptMouse;
	if ( m_MouseHover ) {
		GetCursorPos(&ptMouse);
		if ( ptMouse.x != m_Hover_x || ptMouse.y != m_Hover_y ) {
			m_MouseHover = FALSE;
			callback(tmt_MOUSELEAVE);
		}
	}

	if ( m_ActiveMouseHover ) Fl::add_timeout(double(m_MouseHoverDelay) / 1000.0, cb_time_hover, this);
}

DWORD Fl_Win32_TrayIcon::GetNOTIFYICONDATASizeForOS()
{
	//What will be the return value from this function
	DWORD dwSize = sizeof(NOTIFYICONDATA_1);

	switch (m_ShellVersion) {
	case Version7: //Deliberate fallthrough
	case VersionVista: {
		dwSize = sizeof(NOTIFYICONDATA_4);
		break;
		}
	case Version6: {
		dwSize = sizeof(NOTIFYICONDATA_3);
		break;
		}
	case Version5: {
		dwSize = sizeof(NOTIFYICONDATA_2);
		break;
		}
	default: {
		break;
		}
	}

	return dwSize;
}

Fl_Win32_TrayIcon::~Fl_Win32_TrayIcon()
{
	if ( m_ActiveMouseHover ) {
		Fl::remove_timeout(cb_time_hover, this);
		m_ActiveMouseHover = FALSE;
	}

	//Delete the tray icon
	Delete();

	StopAnimation();
}

void Fl_Win32_TrayIcon::Delete()
{
	//What will be the return value from this function (assume the best)
	BOOL bSuccess = TRUE;

	if (m_bCreated) {
		m_NotifyIconData.uFlags = 0;
		bSuccess = Shell_NotifyIconW(NIM_DELETE, (PNOTIFYICONDATAW)(&m_NotifyIconData));
		m_bCreated = FALSE;
	}
}

BOOL Fl_Win32_TrayIcon::Create(BOOL bShow)
{
	m_NotifyIconData.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;

	if (bShow == FALSE) {
		//if ( m_ShellVersion < Version5) return FALSE; //Only supported on Shell v5 or later
		m_NotifyIconData.uFlags |= NIF_STATE;
		m_NotifyIconData.dwState = NIS_HIDDEN;
		m_NotifyIconData.dwStateMask = NIS_HIDDEN;
	}

	BOOL bSuccess = Shell_NotifyIconW(NIM_ADD, (PNOTIFYICONDATAW)(&m_NotifyIconData));
	if (bSuccess) {
		m_bCreated = TRUE;

		if (bShow == FALSE)
			m_bHidden = TRUE;
	}
	return bSuccess;
}

BOOL Fl_Win32_TrayIcon::IconHide()
{
	//Validate our parameters
	//if (m_ShellVersion < Version5) return FALSE; //Only supported on Shell v5 or later
	if (m_bHidden) return FALSE; //Only makes sense to hide the icon if it is not already hidden

	m_NotifyIconData.uFlags = NIF_STATE;
	m_NotifyIconData.dwState = NIS_HIDDEN;
	m_NotifyIconData.dwStateMask = NIS_HIDDEN;
	BOOL bSuccess = Shell_NotifyIconW(NIM_MODIFY, (PNOTIFYICONDATAW)(&m_NotifyIconData));
	if (bSuccess) m_bHidden = TRUE;
	return bSuccess;
}

BOOL Fl_Win32_TrayIcon::IconShow()
{
	//Validate our parameters
	//if (m_ShellVersion < Version5) return FALSE; //Only supported on Shell v5 or later
	if ( !m_bHidden ) return FALSE; //Only makes sense to hide the icon if it is not already hidden

	if ( ! m_bCreated ) return FALSE;
	m_NotifyIconData.uFlags = NIF_STATE;
	m_NotifyIconData.dwState = 0;
	m_NotifyIconData.dwStateMask = NIS_HIDDEN;
	BOOL bSuccess = Shell_NotifyIconW(NIM_MODIFY, (PNOTIFYICONDATAW)(&m_NotifyIconData));
	if (bSuccess) m_bHidden = FALSE;
	return bSuccess;
}

wchar_t *Fl_Win32_TrayIcon::u2wc(char *s)
{
	if ( s == NULL ) return NULL;

	int n = strlen(s);
	wchar_t *buffer=NULL;
	int lbuf = 0;
	int newn;
	newn = fl_utf8towc(s, n, buffer, lbuf);
	if (newn <= 0 ) return NULL;
	lbuf = newn+8;
	buffer = (wchar_t*)malloc(lbuf * sizeof(wchar_t) + 8);
	fl_utf8towc(s, n, (wchar_t*)buffer, lbuf);

	return buffer;
}

BOOL Fl_Win32_TrayIcon::Create(char *Tooltip, HICON hIcon, BOOL bShow)
{
	//Validate our parameters
	if ( hwnd_ == NULL ) return FALSE;
	if ( ! IsWindow(hwnd_) ) return FALSE;
	if ( hIcon == NULL ) return FALSE;

	//Call the Shell_NotifyIconW function
	m_NotifyIconData.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
	m_NotifyIconData.hWnd = hwnd_;
	m_NotifyIconData.uID = (unsigned int)this;
	m_NotifyIconData.uCallbackMessage = wm_TaskbarCreated;
	m_NotifyIconData.hIcon = hIcon;

	wchar_t *s = u2wc(Tooltip);
	if ( s == NULL ) return FALSE;
	wcscpy(m_NotifyIconData.szTip, s);
	free(s);

	if (bShow == FALSE) {
		//if (m_ShellVersion < Version5) return FALSE; //Only supported on Shell v5 or later
		m_NotifyIconData.uFlags |= NIF_STATE;
		m_NotifyIconData.dwState = NIS_HIDDEN;
		m_NotifyIconData.dwStateMask = NIS_HIDDEN;
	}
	m_bCreated = Shell_NotifyIconW(NIM_ADD, (PNOTIFYICONDATAW)(&m_NotifyIconData));
	if (m_bCreated) {
		if (bShow == FALSE)
			m_bHidden = TRUE;

		//Turn on Shell v5 style behaviour if supported
		if (m_ShellVersion >= Version5)
			SetVersion(NOTIFYICON_VERSION);
	}

	return m_bCreated;
}

BOOL Fl_Win32_TrayIcon::SetVersion(UINT uVersion)
{
	//Validate our parameters
	//if (m_ShellVersion < Version5) return FALSE; //Only supported on Shell v5 or later

	//Call the Shell_NotifyIconW function
	m_NotifyIconData.uVersion = uVersion;
	return Shell_NotifyIconW(NIM_SETVERSION, (PNOTIFYICONDATAW)(&m_NotifyIconData));
}

BOOL Fl_Win32_TrayIcon::Create(char *Tooltip, HICON* phIcons, int nNumIcons, DWORD dwDelay, BOOL bShow)
{
	//Validate our parameters
	if ( phIcons == NULL ) return FALSE;
	if (nNumIcons < 2) return FALSE; //must be using at least 2 icons if you are using animation
	if ( dwDelay < 1 ) return FALSE;

	//let the normal Create function do its stuff
	BOOL bSuccess = Create(Tooltip, phIcons[0], bShow);
	if (bSuccess) {
		//Start the animation
		StartAnimation(phIcons, nNumIcons, dwDelay);
	}

	return bSuccess;
}

BOOL Fl_Win32_TrayIcon::Create(char *Tooltip, char *BalloonText, char *BalloonCaption, UINT nTimeout, BalloonStyle style, HICON hIcon, BOOL bNoSound, 
							   BOOL bLargeIcon, BOOL bRealtime, HICON hBalloonIcon, BOOL bQuietTime, BOOL bShow)
{
	//Validate our parameters
	if ( hwnd_ == NULL ) return FALSE;
	if ( ! IsWindow(hwnd_) ) return FALSE;
	//if ( m_ShellVersion < Version5 ) return FALSE; //Only supported on Shell v5 or later

	//Call the Shell_NotifyIcon function
	m_NotifyIconData.hWnd = hwnd_;
	m_NotifyIconData.uID = (unsigned int)this;
	m_NotifyIconData.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_INFO;
	m_NotifyIconData.uCallbackMessage = wm_TaskbarCreated;
	m_NotifyIconData.hIcon = hIcon;

	wchar_t *s;
	s = u2wc(Tooltip);
	if ( s == NULL ) return FALSE;
	wcscpy(m_NotifyIconData.szTip, s);
	free(s);

	s = u2wc(BalloonText);
	if ( s == NULL ) return FALSE;
	wcscpy(m_NotifyIconData.szInfo, s);
	free(s);

	s = u2wc(BalloonCaption);
	if ( s == NULL ) return FALSE;
	wcscpy(m_NotifyIconData.szInfoTitle, s);
	free(s);

	m_NotifyIconData.uTimeout = nTimeout;
	switch (style) {
	case bsWarning: {
		m_NotifyIconData.dwInfoFlags = NIIF_WARNING;
		break;
	}
	case bsError: {
		m_NotifyIconData.dwInfoFlags = NIIF_ERROR;
		break;
	}
	case bsInfo: {
		m_NotifyIconData.dwInfoFlags = NIIF_INFO;
		break;
	}
	case bsNone: {
		m_NotifyIconData.dwInfoFlags = NIIF_NONE;
		break;
	}
	case bsUser: {
		if (hBalloonIcon) {
			//if (m_ShellVersion < VersionVista) return FALSE;
			m_NotifyIconData.hBalloonIcon = hBalloonIcon;
		} else {
			if (hIcon == NULL) return FALSE; //You forget to provide a user icon
		}
		m_NotifyIconData.dwInfoFlags = NIIF_USER;
		break;
	}
	default: {
		break;
	}
	}
	if (bNoSound)
		m_NotifyIconData.dwInfoFlags |= NIIF_NOSOUND;
	if (bLargeIcon) {
		//if (m_ShellVersion < VersionVista) { //Only supported on Vista Shell
		m_NotifyIconData.dwInfoFlags |= NIIF_LARGE_ICON;
	}
	if (bRealtime) {
		//if (m_ShellVersion < VersionVista) return FALSE; //Only supported on Vista Shell
		m_NotifyIconData.uFlags |= NIF_REALTIME;
	}
	if (bShow == FALSE) {
		//if (m_ShellVersion < Version5) return FALSE; //Only supported on Shell v5 or later
		m_NotifyIconData.uFlags |= NIF_STATE;
		m_NotifyIconData.dwState = NIS_HIDDEN;
		m_NotifyIconData.dwStateMask = NIS_HIDDEN;
	}
	if (bQuietTime) {
		//if (m_ShellVersion < Version7) return FALSE; //Only supported on Windows 7 Shell
		m_NotifyIconData.dwInfoFlags |= NIIF_RESPECT_QUIET_TIME;
	}

	m_bCreated = Shell_NotifyIconW(NIM_ADD, (PNOTIFYICONDATAW)(&m_NotifyIconData));
	if (m_bCreated) {
		if (bShow == FALSE)
			m_bHidden = TRUE;

		//Turn on Shell v5 tray icon behaviour
		SetVersion(NOTIFYICON_VERSION);
	}

	return m_bCreated;
}
BOOL Fl_Win32_TrayIcon::Create(char *Tooltip, char *BalloonText, char *BalloonCaption, UINT nTimeout, BalloonStyle style, HICON* phIcons, int nNumIcons, DWORD dwDelay, 
							   BOOL bNoSound, BOOL bLargeIcon, BOOL bRealtime, HICON hBalloonIcon, BOOL bQuietTime, BOOL bShow)
{
	//Validate our parameters
	if (phIcons == NULL) return FALSE;
	if (nNumIcons < 2) return FALSE; //must be using at least 2 icons if you are using animation
	if ( dwDelay < 1 ) return FALSE;

	//let the normal Create function do its stuff
	BOOL bSuccess = Create(Tooltip, BalloonText, BalloonCaption, nTimeout, style, phIcons[0], bNoSound, bLargeIcon, bRealtime, hBalloonIcon, bQuietTime, bShow);
	if (bSuccess) {
		//Start the animation
		StartAnimation(phIcons, nNumIcons, dwDelay);
	}

	return bSuccess;
}

BOOL Fl_Win32_TrayIcon::SetBalloonDetails(char *BalloonText, char *BalloonCaption, BalloonStyle style, UINT nTimeout, HICON hUserIcon, BOOL bNoSound, BOOL bLargeIcon, BOOL bRealtime, HICON hBalloonIcon)
{
	if (!m_bCreated)
		return FALSE;

	//Call the Shell_NotifyIcon function
	m_NotifyIconData.uFlags = NIF_INFO;

	wchar_t *s;
	s = u2wc(BalloonText);
	if ( s == NULL ) return FALSE;
	wcscpy(m_NotifyIconData.szInfo, s);
	free(s);
	s = u2wc(BalloonCaption);
	if ( s == NULL ) return FALSE;
	wcscpy(m_NotifyIconData.szInfoTitle, s);
	free(s);

	m_NotifyIconData.uTimeout = nTimeout;
	switch (style) {
	case bsWarning: {
		m_NotifyIconData.dwInfoFlags = NIIF_WARNING;
		break;
	}
	case bsError: {
		m_NotifyIconData.dwInfoFlags = NIIF_ERROR;
		break;
	}
	case bsInfo: {
		m_NotifyIconData.dwInfoFlags = NIIF_INFO;
		break;
	}
	case bsNone: {
		m_NotifyIconData.dwInfoFlags = NIIF_NONE;
		break;
	}
	case bsUser: {
		if (hBalloonIcon) {
			m_NotifyIconData.hBalloonIcon = hBalloonIcon;
		} else {
			m_NotifyIconData.uFlags |= NIF_ICON;
			m_NotifyIconData.hIcon = hUserIcon;
		}

		m_NotifyIconData.dwInfoFlags = NIIF_USER;
		break;
	}
	default: {
		break;
	}
	}
	if (bNoSound)
		m_NotifyIconData.dwInfoFlags |= NIIF_NOSOUND;
	if (bLargeIcon)
		m_NotifyIconData.dwInfoFlags |= NIIF_LARGE_ICON;
	if (bRealtime)
		m_NotifyIconData.uFlags |= NIF_REALTIME;

	return Shell_NotifyIconW(NIM_MODIFY, (PNOTIFYICONDATAW)(&m_NotifyIconData));
}

UINT Fl_Win32_TrayIcon::GetBalloonTimeout() const
{
	//Validate our parameters
	//ATLASSERT(m_ShellVersion >= Version5); //Only supported on Shell v5 or later

	UINT nTimeout = 0;
	if (m_bCreated)
		nTimeout = m_NotifyIconData.uTimeout;

	return nTimeout;
}

BOOL Fl_Win32_TrayIcon::SetTooltipText(char *Tooltip)
{
	if (!m_bCreated)
		return FALSE;

	//Call the Shell_NotifyIcon function
	m_NotifyIconData.uFlags = NIF_TIP;
	wchar_t *s;
	s = u2wc(Tooltip);
	if ( s == NULL ) return FALSE;
	wcscpy(m_NotifyIconData.szTip, s);
	free(s);
	return Shell_NotifyIconW(NIM_MODIFY, (PNOTIFYICONDATAW)(&m_NotifyIconData));
}

int	Fl_Win32_TrayIcon::GetTooltipMaxSize()
{
	//Return the cached value if we have one
	if (m_nTooltipMaxSize != -1)
		return m_nTooltipMaxSize;

	//Otherwise calculate the maximum based on the shell version
	if (m_ShellVersion >= Version5) {
		NOTIFYICONDATA_2 dummy;
		m_nTooltipMaxSize = sizeof(dummy.szTip) / sizeof(dummy.szTip[0]) - 1; //The -1 is to allow size for the NULL terminator
	} else {
		NOTIFYICONDATA_1 dummy;
		m_nTooltipMaxSize = sizeof(dummy.szTip) / sizeof(dummy.szTip[0]) - 1; //The -1 is to allow size for the NULL terminator
	}

	return m_nTooltipMaxSize;
}

BOOL Fl_Win32_TrayIcon::SetIcon(HICON hIcon)
{
	//Validate our parameters
	if ( 0 == hIcon ) return FALSE;

	if (!m_bCreated)
		return FALSE;

	//Since we are going to use one icon, stop any animation
	StopAnimation();

	//Call the Shell_NotifyIcon function
	m_NotifyIconData.uFlags = NIF_ICON;
	m_NotifyIconData.hIcon = hIcon;
	return Shell_NotifyIconW(NIM_MODIFY, (PNOTIFYICONDATAW)(&m_NotifyIconData));
}

BOOL Fl_Win32_TrayIcon::SetIcon(LPCTSTR lpIconName)
{
	return SetIcon(LoadIcon(lpIconName));
}

BOOL Fl_Win32_TrayIcon::SetIcon(UINT nIDResource)
{
	return SetIcon(LoadIcon(nIDResource));
}

BOOL Fl_Win32_TrayIcon::SetIcon(HICON* phIcons, int nNumIcons, DWORD dwDelay)
{
	//Validate our parameters
	if (nNumIcons < 2) return FALSE; //must be using at least 2 icons if you are using animation
	if ( NULL == phIcons ) return FALSE;
	if ( dwDelay < 1 ) return FALSE;

	if (!SetIcon(phIcons[0]))
		return FALSE;

	//Start the animation
	StartAnimation(phIcons, nNumIcons, dwDelay);

	return TRUE;
}

HICON Fl_Win32_TrayIcon::LoadIcon(HINSTANCE hInstance, LPCTSTR lpIconName, BOOL bLargeIcon)
{
	return (HICON)(::LoadImage(hInstance, lpIconName, IMAGE_ICON, bLargeIcon ? GetSystemMetrics(SM_CXICON) : GetSystemMetrics(SM_CXSMICON), bLargeIcon ? GetSystemMetrics(SM_CYICON) : GetSystemMetrics(SM_CYSMICON), LR_SHARED));
}

HICON Fl_Win32_TrayIcon::LoadIcon(HINSTANCE hInstance, UINT nIDResource, BOOL bLargeIcon)
{
	return LoadIcon(hInstance, MAKEINTRESOURCE(nIDResource), bLargeIcon);
}

HICON Fl_Win32_TrayIcon::LoadIcon(LPCTSTR lpIconName, BOOL bLargeIcon)
{
	return LoadIcon(fl_display, lpIconName, bLargeIcon);
}

HICON Fl_Win32_TrayIcon::LoadIcon(UINT nIDResource, BOOL bLargeIcon)
{
	return LoadIcon(MAKEINTRESOURCE(nIDResource), bLargeIcon);
}

BOOL Fl_Win32_TrayIcon::SetFocus()
{
	//ATLASSERT(m_ShellVersion >= Version5); //Only supported on Shell v5 or greater

	//Call the Shell_NotifyIcon function
	return Shell_NotifyIconW(NIM_SETFOCUS, (PNOTIFYICONDATAW)(&m_NotifyIconData));
}
/*
LRESULT CTrayNotifyIcon::OnTrayNotification(WPARAM wParam, LPARAM lParam)
{
	//Pull out the icon id
	UINT nID = static_cast<UINT>(wParam);

	//Return quickly if its not for this tray icon
	if (nID != m_NotifyIconData.uID)
		return 0L;

	if ( lParam == WM_MOUSEMOVE ) {

	}

	//Work out if we should show the context menu or handle the double click
	BOOL bShowMenu = (lParam == WM_RBUTTONUP);
	BOOL bDoubleClick = (lParam == WM_LBUTTONDBLCLK);
	if (bShowMenu || bDoubleClick) {
#ifdef _AFX
		CMenu* pSubMenu = m_Menu.GetSubMenu(0);
		ATLASSUME(pSubMenu); //Your menu resource has been designed incorrectly
#else
		CMenuHandle subMenu = m_Menu.GetSubMenu(0);
		ATLASSERT(subMenu.IsMenu());
#endif

		if (bShowMenu) {
			CPoint ptCursor;
			GetCursorPos(&ptCursor);
			::SetForegroundWindow(m_NotifyIconData.hWnd);
#ifdef _AFX
			::TrackPopupMenu(pSubMenu->m_hMenu, TPM_LEFTBUTTON, ptCursor.x, ptCursor.y, 0, m_NotifyIconData.hWnd, NULL);
#else
			::TrackPopupMenu(subMenu, TPM_LEFTBUTTON, ptCursor.x, ptCursor.y, 0, m_NotifyIconData.hWnd, NULL);
#endif
			::PostMessage(m_NotifyIconData.hWnd, WM_NULL, 0, 0);
		} else if (bDoubleClick) { //double click received, the default action is to execute first menu item
			::SetForegroundWindow(m_NotifyIconData.hWnd);
#ifdef _AFX
			UINT nDefaultItem = pSubMenu->GetDefaultItem(GMDI_GOINTOPOPUPS, FALSE);
#else
			UINT nDefaultItem = subMenu.GetMenuDefaultItem(FALSE, GMDI_GOINTOPOPUPS);
#endif
			if (nDefaultItem != -1)
				::SendMessage(m_NotifyIconData.hWnd, WM_COMMAND, nDefaultItem, 0);
		}
	}

	return 1; // handled
}

*/

void Fl_Win32_TrayIcon::cb_time_i()
{
	//increment the icon index
	++m_nCurrentIconIndex;
	m_nCurrentIconIndex = m_nCurrentIconIndex % m_nNumIcons;

	//update the tray icon
	m_NotifyIconData.uFlags = NIF_ICON;
	m_NotifyIconData.hIcon = m_phIcons[m_nCurrentIconIndex];
	Shell_NotifyIconW(NIM_MODIFY, (PNOTIFYICONDATAW)(&m_NotifyIconData));

	Fl::add_timeout(double(m_dwDelay) / 1000.0, cb_time, this);
}

void Fl_Win32_TrayIcon::StartAnimation(HICON* phIcons, int nNumIcons, DWORD dwDelay)
{
	//Validate our parameters
	if (nNumIcons < 2) return; //must be using at least 2 icons if you are using animation
	if (phIcons == NULL ) return;        //array of icon handles must be valid
	if ( dwDelay < 1 ) return;        //must be non zero timer interval

	//Stop the animation if already started
	StopAnimation();

	//Hive away all the values locally
	if (m_phIcons != NULL) return;
	m_phIcons = new HICON[nNumIcons];
	for (int i=0; i<nNumIcons; i++)
		m_phIcons[i] = phIcons[i];
	m_nNumIcons = nNumIcons;

	m_dwDelay = dwDelay;

	//Start up the timer
	m_timeruning = TRUE;
	Fl::add_timeout(double(dwDelay) / 1000.0, cb_time, this);
	//m_nTimerID = SetTimer(m_NotifyIconData.uID, dwDelay);
}

void Fl_Win32_TrayIcon::StopAnimation()
{
	//Kill the timer
	if ( m_timeruning ) {
		Fl::remove_timeout(cb_time, this);
		m_timeruning = FALSE;
	}

	//Free up the memory
	if (m_phIcons) {
		delete [] m_phIcons;
		m_phIcons = NULL;
	}

	//Reset the other animation related variables
	m_nCurrentIconIndex = 0;
	m_nNumIcons = 0;
}

BOOL Fl_Win32_TrayIcon::UsingAnimatedIcon() const
{
	return (m_nNumIcons != 0);
}
/*
HICON CTrayNotifyIcon::GetCurrentAnimationIcon() const
{
	//Valiate our parameters
	ATLASSERT(UsingAnimatedIcon());
	ATLASSUME(m_phIcons);

	return m_phIcons[m_nCurrentIconIndex];
}

BOOL CTrayNotifyIcon::ProcessWindowMessage(HWND hWnd, UINT nMsg, WPARAM wParam, LPARAM lParam, LRESULT& lResult, DWORD dwMsgMapID)
{
	lResult = 0;
	BOOL bHandled = FALSE;

	if (nMsg == wm_TaskbarCreated) {
		lResult = OnTaskbarCreated(wParam, lParam);
		bHandled = TRUE;
	} else if ((nMsg == WM_TIMER) && (wParam == m_NotifyIconData.uID)) {
		OnTimer(m_NotifyIconData.uID);
		bHandled = TRUE; //Do not allow this message to go any further because we have fully handled the message
	} else if (nMsg == WM_DESTROY) {
		OnDestroy();
		bHandled = TRUE;
	}

	return bHandled;
}

void CTrayNotifyIcon::OnDestroy()
{
	StopAnimation();
}

LRESULT CTrayNotifyIcon::OnTaskbarCreated(WPARAM wParam, LPARAM lParam)
{
	//Refresh the tray icon if necessary
	BOOL bShowing = IsShowing();
	Delete(FALSE);
	Create(bShowing);

	return 0;
}

BOOL CTrayNotifyIcon::CreateHelperWindow()
{
	//Let the base class do its thing
	return (CWindowImpl<CTrayNotifyIcon>::Create(NULL, CWindow::rcDefault, _T("CTrayNotifyIcon Helper Window"), WS_OVERLAPPEDWINDOW) != NULL);
}
*/

BOOL Fl_Win32_TrayIcon::WinIsShow()
{
	return IsWindowVisible(hwnd_);
}

void Fl_Win32_TrayIcon::WinShow()
{
	if( IsWindowVisible(hwnd_) ) return;

	ShowWindow(hwnd_, SW_RESTORE);
	SetForegroundWindow(hwnd_);
}
void Fl_Win32_TrayIcon::WinHide()
{
	if( ! IsWindowVisible(hwnd_) ) return;
	
	ShowWindow(hwnd_, SW_HIDE);
}

void Fl_Win32_TrayIcon::WinShowTaskbar()
{
	// FIXIT:
	SetWindowLong(hwnd_, GWL_HWNDPARENT, 0);
	SetParent(hwnd_, NULL);
	SetForegroundWindow(hwnd_);
}

void Fl_Win32_TrayIcon::WinHideTaskbar()
{
	SetWindowLong(hwnd_, GWL_HWNDPARENT, WS_EX_TOOLWINDOW);
}

int Fl_Win32_TrayIcon::msg_handler(int msg)
{
	MSG last_msg = fl_msg; // get the last windows MSG struct we were passed
	// Is this message meant for us, and from our tray icon?
	//if((last_msg.hwnd == mwh) && (last_msg.message = wm_TaskbarCreated)) {
	if( last_msg.message == wm_TaskbarCreated ) {
		Fl_Win32_TrayIcon *o = (Fl_Win32_TrayIcon *)last_msg.wParam;
		return o->msg_handler_i(msg);
	}

	/*
	if ( last_msg.message == WM_SYSCOMMAND ) {
		if((last_msg.wParam & 0xFFF0) == SC_MINIMIZE) {
			//if ( m_ActiveMinToTray ) {
				ShowWindow(last_msg.hwnd, SW_HIDE);
				return 1;
			//}
		}
	}
	*/

	return 0;
}

int Fl_Win32_TrayIcon::msg_handler_i(int msg)
{
	MSG last_msg = fl_msg;

	switch (last_msg.lParam) {
	case WM_MBUTTONDOWN:
		callback(tmt_MBUTTONDOWN);
		return 1;
	case WM_RBUTTONDOWN:
		callback(tmt_RBUTTONDOWN);
		return 1;
	case WM_LBUTTONDOWN: // we want this, but do nothing...
		callback(tmt_LBUTTONDOWN);
		return 1;
	case WM_LBUTTONUP:
		callback(tmt_LBUTTONUP);
		return 1;
	case WM_LBUTTONDBLCLK: // show/hide the main window
		callback(tmt_LBUTTONDBLCLK);
		return 1;
	case WM_RBUTTONUP:
		callback(tmt_RBUTTONUP);
		return 1;
	case WM_RBUTTONDBLCLK: // show the context popup menu
		callback(tmt_RBUTTONDBLCLK);
		return 1;
	case WM_MBUTTONUP:
		callback(tmt_MBUTTONUP);
		return 1;
	case WM_MBUTTONDBLCLK: // does nothing for now - could show a different popup or etc...
		callback(tmt_MBUTTONDBLCLK);
		return 1;
	case WM_MOUSEMOVE:
		//callback(tmt_MOUSEMOVE);
		if ( ! m_ActiveMouseHover ) return 1;
		POINT ptMouse;
		GetCursorPos(&ptMouse);
		m_Hover_x = ptMouse.x;
		m_Hover_y = ptMouse.y;
		if ( ! m_MouseHover ) {
			callback(tmt_MOUSEHOVER);
			m_MouseHover = TRUE;
		}
		return 1;
	default:
		break;
	}

	return 0; // we did not want this message...
}

#endif // #if __FLTK_WIN32__
