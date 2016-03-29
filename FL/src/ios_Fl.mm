#include "fltk_config.h"

#if __FLTK_IPHONEOS__

#include "Fl.H"
#include "x.H"
#include "Fl_Window.H"
#include "Fl_Tooltip.H"
#include "Fl_Printer.H"
#include "Fl_Input_.H"
#include "Fl_Text_Display.H"
#include <stdio.h>
#include <stdlib.h>
#include "flstring.h"
#include <unistd.h>
#include <stdarg.h>
#include <math.h>
#include <limits.h>

//#include <sys/time.h>

#include "Fl_Device.H"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ======================================================

static unsigned make_current_counts = 0; // if > 0, then Fl_Window::make_current() can be called only once
static Fl_X *fl_x_to_redraw = NULL;
static BOOL through_drawRect = NO;

/*
static Fl_Quartz_Graphics_Driver fl_quartz_driver;
static Fl_Display_Device fl_quartz_display(&fl_quartz_driver);
Fl_Display_Device *Fl_Display_Device::_display = &fl_quartz_display; // the platform display
*/

// these pointers are set by the Fl::lock() function:
static void nothing() { }
void (*fl_lock_function)() = nothing;
void (*fl_unlock_function)() = nothing;

static unsigned char islandscape=1;
static int device_w=320, device_h=480;
static int work_y=0;

static void handleUpdateEvent(Fl_Window *window);

static NSDate *endDate = [NSDate dateWithTimeIntervalSinceNow : -0.001];

static Fl_Window *resize_from_system;

static int softkeyboard_isshow_ = 0;
static int softkeyboard_x=0, softkeyboard_y=0, softkeyboard_w=0, softkeyboard_h=0;

// touch
static int mouse_simulate_by_touch_ = 0;
static int touch_type_ = FL_TOUCH_NONE;
static int touch_tapcount_ = 0;
static int touch_finger_ = 0;
#define MaxFinger 10
static int touch_x_[MaxFinger] = {0}, touch_y_[MaxFinger] = {0}, touch_x_root_[MaxFinger] = {0}, touch_y_root_[MaxFinger] = {0};
static UITouch *touch_class[MaxFinger] = {0};
static int touch_end_finger_ = 0;
static int touch_end_x_[MaxFinger] = {0}, touch_end_y_[MaxFinger] = {0}, touch_end_x_root_[MaxFinger] = {0}, touch_end_y_root_[MaxFinger] = {0};
static UITouch *touch_end_class[MaxFinger] = {0};

static UIView *theKeyboard=nil;
static unsigned char keyboard_quickclick_ = 0;

// 0-unknown, 1-iphone, 2-ipad, 3-tv
static unsigned char fl_devicetype = 0;

static int getscreenheight()
{
	islandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
	if ( islandscape ) return device_w;
	else return device_h;
}

// ============= splash ===================
@interface FLTK_splashviewcontroller : UIViewController
{
	UIImageView *splash;
	UIImage *splashPortrait;
	UIImage *splashLandscape;
}
- (void)updateSplashImage : (UIInterfaceOrientation)interfaceOrientation;
@end

@implementation FLTK_splashviewcontroller

- (id)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}

	//[self setWantsFullScreenLayout:YES];

	self->splash = [[UIImageView alloc] init];
	[self setView : self->splash];

	CGSize size = [UIScreen mainScreen].bounds.size;
	int width = (int)size.width;
	int height = (int)size.height;
	int ww = width, hh=height;
	if ( width > height ) {
		width = hh;
		height = ww;
	}

	printf("screen:%d %d\n", (int)[UIScreen mainScreen].bounds.size.width, (int)[UIScreen mainScreen].bounds.size.height);
	printf("Default-%dx%dh.png\n", width, height);
	printf("Default-Landscape-%dx%dh.png\n", height, width);

	self->splashPortrait = [UIImage imageNamed : [NSString stringWithFormat : @"Default-Portrait-1366h.png"]];
	if (!self->splashPortrait) {
		printf("cannot load default-xxxh.png\n");
		self->splashPortrait = [UIImage imageNamed : @"Default.png"];
	}

	self->splashLandscape = [UIImage imageNamed : [NSString stringWithFormat : @"Default-Landscape-1366h.png"]];
	if (!self->splashLandscape) self->splashLandscape = [UIImage imageNamed : @"Default-Landscape.png"];

	//if (!self->splashLandscape && self->splashPortrait) self->splashLandscape = [[UIImage alloc] initWithCGImage: self->splashPortrait.CGImage scale: 1.0 orientation: UIImageOrientationRight];

	if (self->splashPortrait) [self->splashPortrait retain];
	if (self->splashLandscape) [self->splashLandscape retain];

	[self updateSplashImage : [[UIApplication sharedApplication] statusBarOrientation]];

	return self;
}

- (NSUInteger)supportedInterfaceOrientations
{
	NSUInteger orientationMask = UIInterfaceOrientationMaskAll;

	// Don't allow upside-down orientation on the phone, so answering calls is in the natural orientation
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
		orientationMask &= ~UIInterfaceOrientationMaskPortraitUpsideDown;
	}

	return orientationMask;
}

- (BOOL)shouldAutorotateToInterfaceOrientation : (UIInterfaceOrientation)orient
{
	NSUInteger orientationMask = [self supportedInterfaceOrientations];
	return (orientationMask & (1 << orient));
}

- (void)willAnimateRotationToInterfaceOrientation : (UIInterfaceOrientation)interfaceOrientation duration : (NSTimeInterval)duration
{
	[self updateSplashImage : interfaceOrientation];
}

- (void)updateSplashImage : (UIInterfaceOrientation)interfaceOrientation
{
	UIImage *image;

	if (UIInterfaceOrientationIsLandscape(interfaceOrientation)) image = self->splashLandscape;
	else image = self->splashPortrait;

	if (image) splash.image = image;
}

@end

static UIWindow *launch_window=nil;

// ************************* main begin ****************************************
static int forward_argc;
static char **forward_argv;
static int exit_status;

static unsigned char EventPumpEnabled_ = 0;
static void SetEventPump(unsigned char enabled)
{
	EventPumpEnabled_ = enabled;
}

@interface FLTKUIKitDelegate : NSObject<UIApplicationDelegate>
{
}
+ (NSString *)getAppDelegateClassName;
@end

@implementation FLTKUIKitDelegate

+ (NSString *)getAppDelegateClassName
{
	return @"FLTKUIKitDelegate";
}

- (id)init
{
	self = [super init];
	return self;
}

- (void)postFinishLaunch
{
	/*
	if (launch_window) {
	    [launch_window release];
	    launch_window = NULL;
	}
	 //*/

	[[UIApplication sharedApplication] setStatusBarHidden : NO];

	islandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);

	CGSize cs = [UIScreen mainScreen].bounds.size;
	int w = (int)cs.width, h = (int)cs.height;
	if ( w > h ) {
		device_w = h;
		device_h = w;
	} else {
		device_w = w;
		device_h = h;
	}

	CGRect bounds = [[UIScreen mainScreen] applicationFrame];
	work_y = bounds.origin.y;

	//printf("postFinishLaunch: islandscape-%d, device:%d %d, work_y:%d\n", islandscape, device_w, device_h, work_y);

	/* run the user's application, passing argc and argv */
	SetEventPump(1);
	exit_status = IOS_main(forward_argc, forward_argv);
	SetEventPump(0);

	[[NSNotificationCenter defaultCenter] removeObserver : self];

	if (launch_window) {
		[launch_window release];
		launch_window = NULL;
	}

	/* exit, passing the return status from the user's application */
	/* We don't actually exit to support applications that do setup in
	 * their main function and then allow the Cocoa event loop to run.
	 */
	/* exit(exit_status); */
}

- (BOOL)application : (UIApplication *)application didFinishLaunchingWithOptions : (NSDictionary *)launchOptions
{
	/*
	// splash
	CGRect crect =[[UIScreen mainScreen] bounds];
	launch_window = [[UIWindow alloc] initWithFrame:crect];
	FLTK_splashviewcontroller *splashViewController = [[FLTK_splashviewcontroller alloc] init];
	launch_window.rootViewController = splashViewController;
	[launch_window addSubview:splashViewController.view];
	[launch_window makeKeyAndVisible];
	 //*/

	/*
	AppDelegate *delegate = [UIApplication sharedApplication].delegate;
	UIWindow *mainWindow = delegate.window;
	[mainWindow addSubview:launchView];

	[UIView animateWithDuration:0.6f delay:0.5f options:UIViewAnimationOptionBeginFromCurrentState animations:^{
	    launchView.alpha = 0.0f;
	    launchView.layer.transform = CATransform3DScale(CATransform3DIdentity, 1.5f, 1.5f, 1.0f);
	} completion:^(BOOL finished) {
	    [launchView removeFromSuperview];
	}];
	 */

	//
	NSInteger uii = [[UIDevice currentDevice] userInterfaceIdiom];
	if ( uii == UIUserInterfaceIdiomPhone) {
		fl_devicetype = 1;
	} else if ( uii == UIUserInterfaceIdiomPad ) {
		fl_devicetype = 2;
	} else {
		fl_devicetype = 3;
	}

	/*
	if ( SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"9.0") ) {
	    if ( uii == UIUserInterfaceIdiomTV ) fl_devicetype = 3;
	}
	*/

	/* Set working directory to resource path */
	[[NSFileManager defaultManager] changeCurrentDirectoryPath : [[NSBundle mainBundle] resourcePath]];

	[self performSelector : @selector(postFinishLaunch) withObject : nil afterDelay : 0.0];

	return YES;
}

- (void)applicationWillTerminate : (UIApplication *)application
{
	printf("applicationWillTerminate\n");

	fl_lock_function();
	while (Fl_X::first) {
		Fl_Window *win = Fl::first_window();
		if (win->parent()) win = win->top_window();
		Fl_Widget_Tracker wt(win); // track the window object
		Fl::handle(FL_CLOSE, win);
		if (wt.exists() && win->shown()) { // the user didn't close win
			//    reply = NSTerminateCancel; // so we return to the main program now
			break;
		}
	}
	/*
	while (Fl_X::first) {
		Fl_X *x = Fl_X::first;
		Fl::handle(FL_CLOSE, x->w);
		Fl::do_widget_deletion();
		if (Fl_X::first == x) {
			// FLTK has not closed all windows, so we return to the main program now
			break;
		}
	}
	 */
	fl_unlock_function();
}

- (void)applicationDidReceiveMemoryWarning : (UIApplication *)application
{
	//SDL_SendAppEvent(SDL_APP_LOWMEMORY);
	// Do something
}

// http://justcoding.iteye.com/blog/1473350
/*
首次运行：
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
- (void)applicationDidBecomeActive:(UIApplication *)application

首次关闭（home）：
- (void)applicationWillResignActive:(UIApplication *)application
- (void)applicationDidEnterBackground:(UIApplication *)application

再次运行：
- (void)applicationWillEnterForeground:(UIApplication *)application
- (void)applicationDidBecomeActive:(UIApplication *)application

再次关闭：
- (void)applicationWillResignActive:(UIApplication *)application
- (void)applicationDidEnterBackground:(UIApplication *)application
*/
- (void) applicationWillResignActive : (UIApplication*)application
{
	printf("applicationWillResignActive\n");
	// FIXIT: send event
}

- (void) applicationDidEnterBackground : (UIApplication*)application
{
	printf("applicationDidEnterBackground\n");
	/*
	 FIXIT:
	fl_lock_function();
	Fl_X *x;
	for (x = Fl_X::first; x; x = x->next) {
		Fl_Window *window = x->w;
		if (!window->parent()) Fl::handle(FL_HIDE, window);
	}
	fl_unlock_function();
	 */
}

- (void) applicationWillEnterForeground : (UIApplication*)application
{
	printf("applicationWillEnterForeground\n");
	/*
	 FIXIT:
	fl_lock_function();
	Fl_X *x;
	for (x = Fl_X::first; x; x = x->next) {
		Fl_Window *w = x->w;
		if (!w->parent()) {
			Fl::handle(FL_SHOW, w);
		}
	}
	fl_unlock_function();
	 */
}

- (void) applicationDidBecomeActive : (UIApplication*)application
{
	printf("applicationDidBecomeActive\n");
	// FIXIT: send event
}

- (BOOL)application : (UIApplication *)application openURL : (NSURL *)url sourceApplication : (NSString *)sourceApplication annotation : (id)annotation
{
	/*
	    NSURL *fileURL = [url filePathURL];
	    if (fileURL != nil) {
	        SDL_SendDropFile([[fileURL path] UTF8String]);
	    } else {
	        SDL_SendDropFile([[url absoluteString] UTF8String]);
	    }
	*/
	// FIXIT:

	return YES;
}

@end

#ifdef main
#undef main
#endif
int main(int argc, char **argv)
{
	int i;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* store arguments */
	forward_argc = argc;
	forward_argv = (char **)malloc((argc+1) * sizeof(char *));
	for (i = 0; i < argc; i++) {
		forward_argv[i] = (char*)malloc( (strlen(argv[i])+1) * sizeof(char));
		strcpy(forward_argv[i], argv[i]);
	}
	forward_argv[i] = NULL;

	/* Give over control to run loop, FLTKUIKitDelegate will handle most things from here */
	UIApplicationMain(argc, argv, NULL, [FLTKUIKitDelegate getAppDelegateClassName]);

	/* free the memory we used to hold copies of argc and argv */
	for (i = 0; i < forward_argc; i++) {
		free(forward_argv[i]);
	}
	free(forward_argv);

	[pool release];
	return exit_status;
}
// ************************* main end ****************************************

//==============================================================================
@interface FLView : UIView <UITextViewDelegate>
{
	BOOL in_key_event; // YES means keypress is being processed by handleEvent
	BOOL need_handle; // YES means Fl::handle(FL_KEYBOARD,) is needed after handleEvent processing
	NSInteger identifier;
	NSRange selectedRange;

@public
	UITextView* hiddenTextView;
	Fl_Window *flwindow;
}
- (FLView*) initWithFlWindow : (Fl_Window*)win contentRect : (CGRect) rect;
- (Fl_Window *)getFl_Window;
- (void) dealloc;

- (void) drawRect : (CGRect) r;
- (BOOL) becomeFirstResponder;
- (BOOL) resignFirstResponder;
- (BOOL) canBecomeFirstResponder;
@end

//==============================================================================
@interface FLViewController : UIViewController
{
}
- (NSUInteger) supportedInterfaceOrientations;
- (BOOL) shouldAutorotateToInterfaceOrientation : (UIInterfaceOrientation) interfaceOrientation;
- (void) willRotateToInterfaceOrientation : (UIInterfaceOrientation) toInterfaceOrientation duration : (NSTimeInterval) duration;
- (void) didRotateFromInterfaceOrientation : (UIInterfaceOrientation) fromInterfaceOrientation;
- (BOOL)prefersStatusBarHidden;
@end

//==============================================================================
@interface FLWindow : UIWindow
{
	Fl_Window *w;
}
- (FLWindow *)initWithFlWindow : (Fl_Window *)flw contentRect : (CGRect)rect;
- (Fl_Window *)getFl_Window;
- (void) becomeKeyWindow;
@end

//******************* spot **********************************

// public variables
CGContextRef fl_gc = 0;
void *fl_capture = 0;           // (NSWindow*) we need this to compensate for a missing(?) mouse capture
bool fl_show_iconic;                    // true if called from iconize() - shows the next created window in collapsed state
Window fl_window;
Fl_Window *Fl_Window::current_;
Fl_Fontdesc *fl_fonts = Fl_X::calc_fl_fonts();

static Fl_Window *spot_win_=0;

static void ios_reset_spot()
{
	FLView *view = (FLView*)[[Fl_X::first->xid rootViewController] view];
	if ( [view->hiddenTextView isFirstResponder] ) {
		[view->hiddenTextView resignFirstResponder];
		[view->hiddenTextView becomeFirstResponder];

		//printf("ios reset spot\n");
	}
	//if ( ! [view->hiddenTextView isFirstResponder] ) [view->hiddenTextView becomeFirstResponder];
}

void fl_reset_spot()
{
	//printf("reset_spot\n");
	if ( Fl_X::first == NULL ) return;
	FLView *view = (FLView*)[[Fl_X::first->xid rootViewController] view];
	if ( ! [view->hiddenTextView isFirstResponder] ) return;
	[view->hiddenTextView resignFirstResponder];
}

void fl_set_spot(int font, int size, int X, int Y, int W, int H, Fl_Window *win)
{
	//printf("fl_set_spot\n");
	//*
	if ( ! win ) {
		//printf("fl_set_spot cancel\n");
		spot_win_ = 0;
		return;
	}
	//*/

	//[Fl_X::i(win)->xid becomeFirstResponder];
	//[Fl_X::i(win)->xid makeKeyAndVisible];

	FLWindow *fwin = Fl_X::i(win)->xid;
	//FLView *view = (FLView*)[[Fl_X::first->xid rootViewController] view];
	FLView *view = (FLView*)[[Fl_X::i(win)->xid rootViewController] view];

	int height = fl_height(font, size);
	if ( X > 0 && Y > height && view ) {
		CGRect r;
		r.origin.x = X;
		r.origin.y = Y-height;
		r.size.width = 120;
		r.size.height = 50;
		view->hiddenTextView.frame = r;
		//printf("set spot:%d %d\n", X, Y-height);
	}

	if ( ! [view->hiddenTextView isFirstResponder] ) [view->hiddenTextView becomeFirstResponder];
	if ( ! [view isFirstResponder] ) [view becomeFirstResponder];

	[fwin becomeFirstResponder];
	[fwin makeKeyAndVisible];

	//[UIApplication sharedApplication]

	spot_win_ = win;
	//printf("set_spot\n");
}

void fl_set_status(int x, int y, int w, int h)
{
	//printf("set_status\n");
}

void fl_open_display()
{
	static char beenHereDoneThat = 0;

	if (beenHereDoneThat) return;
	beenHereDoneThat = 1;

	// FIXIT: do some init thing
}

// so a CGRect matches exactly what is denoted x,y,w,h for clipping purposes
CGRect fl_cgrectmake_cocoa(int x, int y, int w, int h)
{
	return CGRectMake(x, y, w > 0 ? w - 0.9 : 0, h > 0 ? h - 0.9 : 0);
}

double fl_ios_flush_and_wait(double time_to_wait)  //ok
{
	if ( 0 == EventPumpEnabled_ ) return 0.0;

	Fl::flush();

	//printf("start\n");
	//[[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.001]];
	[[NSRunLoop currentRunLoop] runMode : NSDefaultRunLoopMode beforeDate : [NSDate dateWithTimeIntervalSinceNow : 0.001f/*time_to_wait*/]];
	//[[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.001f]];
	/*
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:endDate];
	[pool release];
	*/
	//printf("runloop end\n");

	return 0.0;
}

/*
 * Check if there is actually a message pending
 */
int fl_ready() // ok
{
	return 1;
}

void Fl::enable_im()
{
}

void Fl::disable_im()
{
}

/*
 * smallest x coordinate in screen space of work area of menubar-containing display
 */
int Fl::x() // ok
{
	return 0;
}

/*
 * smallest y coordinate in screen space of work area of menubar-containing display
 */
int Fl::y() // ok
{
	return work_y;
}

/*
 * width of work area of menubar-containing display
 */
int Fl::w() // ok
{
	//islandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
	if ( islandscape ) return device_h;
	else return device_w;

	//CGSize size = [UIScreen mainScreen].bounds.size;
	//return (int)size.width;
	//return device_w;
}

/*
 * height of work area of menubar-containing display
 */
int Fl::h() // ok
{
	//islandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
	if ( islandscape ) return device_w-work_y;
	else return device_h-work_y;

	//CGSize size = [UIScreen mainScreen].bounds.size;
	//return (int)size.height - work_y;
	//return device_h-work_y;
}

// computes the work area of the nth screen (screen #0 has the menubar)
void Fl_X::screen_work_area(int &X, int &Y, int &W, int &H, int n) // ok
{
	X = 0;
	Y = 0;
	if ( islandscape ) {
		W = device_h;
		H = device_w;
	} else {
		W = device_w;
		H = device_h;
	}

	//printf("Fl_X::screen_work_area:%d %d, islandscape:%d\n", W, H, islandscape);

	/*
	CGSize size = [UIScreen mainScreen].bounds.size;
	X = 0;
	Y = 0;
	W = (int)size.width;
	H = (int)size.height;
	 */
	//W = device_w;
	//H = device_h;
}

/*
 * get the current mouse pointer world coordinates
 */
void Fl::get_mouse(int &x, int &y)
{
	/*
		fl_open_display();
		NSPoint pt = [NSEvent mouseLocation];
		x = int(pt.x);
		y = int(main_screen_height - pt.y);
	*/
}


/*
 * Gets called when a window is created, resized, or deminiaturized
 */
static void handleUpdateEvent(Fl_Window *window)
{
	if ( !window ) return;

	Fl_X *i = Fl_X::i( window );

	//bool previous = i->mapped_to_retina();
	/*
	// rewrite next call that requires 10.7 and therefore triggers a compiler warning on old SDKs
	//NSSize s = [[i->xid contentView] convertSizeToBacking:NSMakeSize(10, 10)];
	typedef CGSize (*convertSizeIMP)(id, SEL, CGSize);
	static convertSizeIMP addr = (convertSizeIMP)[UIView instanceMethodForSelector:@selector(convertSizeToBacking:)];
	CGSize s = addr([i->xid contentView], @selector(convertSizeToBacking:), UIMakeSize(10, 10));
	i->mapped_to_retina( int(s.width + 0.5) > 10 );
	if (i->wait_for_expose == 0 && previous != i->mapped_to_retina()) i->changed_resolution(true);
	 */

	i->wait_for_expose = 0;

	if ( i->region ) {
		XDestroyRegion(i->region);
		i->region = 0;
	}
	window->clear_damage(FL_DAMAGE_ALL);
	i->flush();
	window->clear_damage();

	/*
	if (!window) return;
	Fl_X *i = Fl_X::i(window);
	i->wait_for_expose = 0;

	if (i->region) {
		XDestroyRegion(i->region);
		i->region = 0;
	}

	for (Fl_X *cx = i->xidChildren; cx; cx = cx->xidNext) {
		if (cx->region) {
			XDestroyRegion(cx->region);
			cx->region = 0;
		}
		cx->w->clear_damage(FL_DAMAGE_ALL);
	    CGContextRef gc = (CGContextRef)UIGraphicsGetCurrentContext();//[[UIGraphicsPopContext currentContext] graphicsPort];
		CGContextSaveGState(gc); // save original context
		cx->flush();
		CGContextRestoreGState(gc); // restore original context
		cx->w->clear_damage();
	}
	window->clear_damage(FL_DAMAGE_ALL);
	i->flush();
	window->clear_damage();
	 */
}

void Fl_Window::fullscreen_x()
{
	_set_fullscreen();
	/* On OS X < 10.6, it is necessary to recreate the window. This is done with hide+show. */
	[[UIApplication sharedApplication] setStatusBarHidden : YES];
	//hide();
	//show();
	Fl::handle(FL_FULLSCREEN, this);
}

void Fl_Window::fullscreen_off_x(int X, int Y, int W, int H)
{
	_clear_fullscreen();
	[[UIApplication sharedApplication] setStatusBarHidden : NO];
	//hide();
	resize(X, Y, W, H);
	//show();
	Fl::handle(FL_FULLSCREEN, this);
}

/*
 * Initialize the given port for redraw and call the window's flush() to actually draw the content
 */
void Fl_X::flush()
{
	//*
	if (through_drawRect ) { //|| w->as_gl_window()) {
		make_current_counts = 1;
		w->flush();
		make_current_counts = 0;
		Fl_X::q_release_context();
		return;
	}
	//*/
	// have Cocoa immediately redraw the window's view
	FLView *view = (FLView *)[[fl_xid(w) rootViewController] view];
	fl_x_to_redraw = this;
	[view setNeedsDisplay];//: YES];
	// will send the drawRect: message to the window's view after having prepared the adequate NSGraphicsContext
	//[view displayIfNeededIgnoringOpacity];
	fl_x_to_redraw = NULL;
}

int Fl_X::fake_X_wm(const Fl_Window *w, int &X, int &Y, int &bt, int &bx, int &by)
{
	return 0;
	/*
	int W, H, xoff, yoff, dx, dy;
	int ret = bx = by = bt = 0;
	if (w->border() && !w->parent()) {
	    if (w->maxw != w->minw || w->maxh != w->minh) {
	        ret = 2;
	    } else {
	        ret = 1;
	    }
	    get_window_frame_sizes(bx, by, bt);
	}
	// The coordinates of the whole window, including non-client area
	xoff = bx;
	yoff = by + bt;
	dx = 2 * bx;
	dy = 2 * by + bt;
	X = w->x() - xoff;
	Y = w->y() - yoff;
	W = w->w() + dx;
	H = w->h() + dy;

	if (w->parent()) return 0;

	// Proceed to positioning the window fully inside the screen, if possible

	// let's get a little elaborate here. Mac OS X puts a lot of stuff on the desk
	// that we want to avoid when positioning our window, namely the Dock and the
	// top menu bar (and even more stuff in 10.4 Tiger). So we will go through the
	// list of all available screens and find the one that this window is most
	// likely to go to, and then reposition it to fit withing the 'good' area.
	//  Rect r;
	// find the screen, that the center of this window will fall into
	int R = X + W, B = Y + H; // right and bottom
	//int cx = (X+ R) / 2, cy = (Y + B) / 2; // center of window;
	UIScreen *gd = [UIScreen mainScreen];
	CGRect r;
	r = [gd bounds];
	r.origin.y = device_h - (r.origin.y + r.size.height); // use FLTK's multiscreen coordinates

	if (gd) {
	    r = [gd applicationFrame];// visibleFrame];
	    r.origin.y = device_h - (r.origin.y + r.size.height); // use FLTK's multiscreen coordinates
	    if (R > r.origin.x + r.size.width) X -= int(R - (r.origin.x + r.size.width));
	    if (B > r.size.height + r.origin.y) Y -= int(B - (r.size.height + r.origin.y));
	    if (X < r.origin.x) X = int(r.origin.x);
	    if (Y < r.origin.y) Y = int(r.origin.y);
	}

	// Return the client area's top left corner in (X,Y)
	X += xoff;
	Y += yoff;

	return ret;
	 */
}


/*
 * go ahead, create that (sub)window
 */
//*
void Fl_X::make(Fl_Window *w)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	Fl_Group::current(0);
	fl_open_display();
	if (w->parent()) {
		w->border(0);
		fl_show_iconic = 0;
	}
	if (fl_show_iconic && !w->parent()) { // prevent window from being out of work area when created iconized
		int sx, sy, sw, sh;
		Fl::screen_work_area (sx, sy, sw, sh, w->x(), w->y());
		if (w->x() < sx) w->x(sx);
		if (w->y() < sy) w->y(sy);
	}
	int xp = w->x();
	int yp = w->y();
	int wp = w->w();
	int hp = w->h();
	if (w->size_range_set) {

	} else {
		if (w->resizable()) {
			Fl_Widget *o = w->resizable();
			int minw = o->w();
			if (minw > 100) minw = 100;
			int minh = o->h();
			if (minh > 100) minh = 100;
			w->size_range(w->w() - o->w() + minw, w->h() - o->h() + minh, 0, 0);
		} else {
			w->size_range(w->w(), w->h(), w->w(), w->h());
		}
	}
	int xwm = xp, ywm = yp, bt, bx, by;
	//fake_X_wm(w, xwm, ywm, bt, bx, by);
	/*
	if (!fake_X_wm(w, xwm, ywm, bt, bx, by)) {
	    // menu windows and tooltips
	    if (w->modal()||w->tooltip_window()) {
	        winlevel = modal_window_level();
	    }
	}
	 //*/

	if (by+bt) {
		wp += 2*bx;
		hp += 2*by+bt;
	}
	if (w->force_position()) {
		if (!Fl::grab()) {
			xp = xwm;
			yp = ywm;
			w->x(xp);
			w->y(yp);
		}
		xp -= bx;
		yp -= by+bt;
	}

	Fl_X* x = new Fl_X();
	x->other_xid = 0; // room for doublebuffering image map. On OS X this is only used by overlay windows
	x->region = 0;
	x->subRect(0);
	//x->cursor = NULL;
	x->gc = 0;
	x->mapped_to_retina(false);
	x->changed_resolution(false);
	x->in_windowDidResize(false);

	CGRect crect;
	if (w->fullscreen_active()) {
		int top, bottom, left, right;
		int sx, sy, sw, sh, X, Y, W, H;

		top = w->fullscreen_screen_top;
		bottom = w->fullscreen_screen_bottom;
		left = w->fullscreen_screen_left;
		right = w->fullscreen_screen_right;

		if ((top < 0) || (bottom < 0) || (left < 0) || (right < 0)) {
			top = Fl::screen_num(w->x(), w->y(), w->w(), w->h());
			bottom = top;
			left = top;
			right = top;
		}

		Fl::screen_xywh(sx, sy, sw, sh, top);
		Y = sy;
		Fl::screen_xywh(sx, sy, sw, sh, bottom);
		H = sy + sh - Y;
		Fl::screen_xywh(sx, sy, sw, sh, left);
		X = sx;
		Fl::screen_xywh(sx, sy, sw, sh, right);
		W = sx + sw - X;

		w->resize(X, Y, W, H);
	}
	crect.origin.x = w->x();// + w->w(); // correct origin set later for subwindows
	crect.origin.y = w->y();// + w->h();//device_h - (w->y() + w->h());
	crect.size.width=w->w();
	crect.size.height=w->h();
	FLWindow *cw = [[FLWindow alloc] initWithFlWindow : w contentRect : crect];
	cw.autoresizesSubviews = YES;
	//CGAffineTransform transform = {0, 1, -1, 0, 0, 0};
	//Fl_X::i(this)->xid.transform = transform;//CGAffineTransformIdentity;
	//cw.transform = transform;
	[cw setFrame : crect]; // setFrameOrigin:crect.origin];
	/*
	if (!w->parent()) {
	    [cw setHasShadow:YES];
	    [cw setAcceptsMouseMovedEvents:YES];
	}
	 */

	//printf("cw=%x, x=%x\n", cw, x);
	x->xid = cw;
	x->w = w;
	w->flx = x;
	x->wait_for_expose = 1;
	if (!w->parent()) {
		x->next = Fl_X::first;
		Fl_X::first = x;
	} else if (Fl_X::first) {
		x->next = Fl_X::first->next;
		Fl_X::first->next = x;
	} else {
		x->next = NULL;
		Fl_X::first = x;
	}

	CGRect crectview;
	crectview.size.width = w->w();
	crectview.size.height = w->h();
	crectview.origin.x = 0.0;
	crectview.origin.y = 0.0;
	FLView *myview = [[FLView alloc] initWithFlWindow : w contentRect : crectview ]; // initWithFrame:crect];
	myview.multipleTouchEnabled = YES;
	myview.opaque = NO;
	myview.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent : 0];
	//[cw setContentView:myview];

	FLViewController* controller = [[FLViewController alloc] init];
	controller.view = myview;
	cw.rootViewController = controller;
	[cw addSubview : myview];
	//controller.navigationController.interactivePopGestureRecognizer.delaysTouchesBegan = NO;

	//[myview release];
	//[cw setLevel:winlevel];
	//cw.windowLevel = UIWindowLevelNormal;

	if (!w->force_position()) {
		CGRect rect_center;
		rect_center.origin.x = (Fl::w() - w->w())/2;
		rect_center.origin.y = (getscreenheight() - w->h()) / 2;
		rect_center.size.width = w->w();
		rect_center.size.height = w->h();
		[cw setFrame : rect_center];
		/*
		if (w->modal()) {
		    [cw setFrame:]
		    [cw center];
		} else if (w->non_modal()) {
		    [cw center];
		} else {
		    [cw center];
		    //static CGPoint delta = CGPointZero;
		    //delta = [cw cascadeTopLeftFromPoint:delta];
		}
		 */
		crect = [cw frame]; // synchronize FLTK's and the system's window coordinates
		w->x(int(crect.origin.x));
		//w->y(int(device_h - (crect.origin.y + w->h())));
		w->y(int(crect.origin.y));
	}
	if ( w->parent() ) {
		int wx=w->x(), wy=w->y();
		for (Fl_Window* wp = w->window(); wp; wp = wp->window()) {
			wx += wp->x();
			wy += wp->y();
		}
		CGRect rect_sub;
		rect_sub.origin.x = wx;
		rect_sub.origin.y = wy;
		rect_sub.size.width = w->w();
		rect_sub.size.height = w->h();
		[cw setFrame : rect_sub];

		cw.windowLevel = UIWindowLevelAlert;
		[cw makeKeyWindow];
		[cw makeKeyAndVisible];
	}

	if(w->menu_window()) { // make menu windows slightly transparent
		[cw.rootViewController.view setAlpha : 0.97f];
	}
	// Install DnD handlers
	//[myview registerForDraggedTypes:[NSArray arrayWithObjects:UTF8_pasteboard_type,  NSFilenamesPboardType, nil]];

	if (w->size_range_set) w->size_range_();

	if ( w->border() || (!w->modal() && !w->tooltip_window()) ) {
		Fl_Tooltip::enter(0);
	}

	if (w->modal()) Fl::modal_ = w;

	w->set_visible();
	if ( w->border() || (!w->modal() && !w->tooltip_window()) ) Fl::handle(FL_FOCUS, w);
	//[cw setDelegate:[FLWindowDelegate singleInstance]];
	if (fl_show_iconic) {
		fl_show_iconic = 0;
		w->handle(FL_SHOW); // create subwindows if any
		//[cw recursivelySendToSubwindows:@selector(display)];  // draw the window and its subwindows before its icon is computed
		//[cw miniaturize:nil];
	} else if (w->parent()) { // a subwindow
		//[cw setIgnoresMouseEvents:YES]; // needs OS X 10.2
		// next 2 statements so a subwindow doesn't leak out of its parent window
		[cw setOpaque : NO];
		[cw setBackgroundColor : [UIColor clearColor]]; // transparent background color
		//[cw setSubwindowFrame];
		//[cw makeKeyAndVisible];
		//cw.windowLevel = UIWindowLevelAlert;
		[cw makeKeyAndVisible];

		// needed if top window was first displayed miniaturized
		//FLWindow *pxid = fl_xid(w->top_window());
		//[pxid makeFirstResponder:[pxid contentView]];
	} else { // a top-level window
		//[cw makeKeyAndOrderFront:nil];
		[cw makeKeyAndVisible];
	}

	int old_event = Fl::e_number;
	w->handle(Fl::e_number = FL_SHOW);
	Fl::e_number = old_event;

	// if (w->modal()) { Fl::modal_ = w; fl_fix_focus(); }
	[pool release];
}
//*/

/*
static void make(Fl_Window *w)
{
    if (w->parent()) {      // create a subwindow
		Fl_Group::current(0);
		// our subwindow needs this structure to know about its clipping.
		Fl_X *x = new Fl_X;
		x->subwindow = true;
		x->other_xid = 0;
		x->region = 0;
		x->subRegion = 0;
		x->gc = 0;          // stay 0 for Quickdraw; fill with CGContext for Quartz
		w->set_visible();
		Fl_Window *win = w->window();
		Fl_X *xo = Fl_X::i(win);
		if (xo) {
			x->xidNext = xo->xidChildren;
			x->xidChildren = 0L;
			xo->xidChildren = x;
			x->xid = win->i->xid;
			x->w = w; w->i = x;
			x->wait_for_expose = 0;
			{
				Fl_X *z = xo->next; // we don't want a subwindow in Fl_X::first
				xo->next = x;
				x->next = z;
			}
			int old_event = Fl::e_number;
			w->handle(Fl::e_number = FL_SHOW);
			Fl::e_number = old_event;
			w->redraw();      // force draw to happen
		}

	} else {            // create a desktop window
        //printf("make\n");
		Fl_Group::current(0);
		fl_open_display();

		if (w->non_modal() && Fl_X::first / *&& !fl_disable_transient_for* /) {
			// find some other window to be "transient for":
			Fl_Window *w = Fl_X::first->w;
			while (w->parent()) w = w->window(); // todo: this code does not make any sense! (w!=w??)
		}

		Fl_X *x = new Fl_X();
		x->subwindow = false;
		x->other_xid = 0; // room for doublebuffering image map. On OS X this is only used by overlay windows
		x->region = 0;
		x->subRegion = 0;
		x->xidChildren = 0;
		x->xidNext = 0;
		x->gc = 0;

		CGRect crect;
		if (w->fullscreen_active()) {
            [[UIApplication sharedApplication] setStatusBarHidden: YES];
            int sx, sy, sw, sh;
            Fl::screen_work_area(sx, sy, sw, sh);
			w->x(sx);
            w->y(sy);
			w->w(sw);
            w->h(sh);

			//w->resize(X, Y, W, H);
        } else {
            if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
                int y_ios6 = w->y();
                if (y_ios6 <= work_y) y_ios6 = 0;
                //else y_ios6 -= work_y;
                w->y(y_ios6);
            }
        }
        //printf("make(), x=%d, y=%d, w=%d, h=%d\n", w->x(), w->y(), w->w(), w->h());

        crect.origin.x = w->x();
        crect.origin.y = w->y();
		crect.size.width = w->w();
		crect.size.height = w->h();
		FLWindow *cw = [[FLWindow alloc] initWithFlWindow: w contentRect: crect];
        //if (w->fullscreen_active()) cw.windowLevel = UIWindowLevelAlert;
        cw.autoresizesSubviews = NO;
        cw.opaque = YES;
        cw.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];

        crect.size.width = w->w();
        crect.size.height = w->h();
        crect.origin.x = 0.0;
        crect.origin.y = 0.0;
		FLView *myview = [[FLView alloc] initWithFlWindow: w contentRect: crect];
        myview.multipleTouchEnabled = YES;
        myview.opaque = YES;
        myview.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];

		FLViewController* controller;
		controller = [[FLViewController alloc] init];
        //controller.automaticallyAdjustsScrollViewInsets = NO;
        //myview.autoresizesSubviews = NO;
        //if (IOS_VERSION_7_OR_ABOVE) {
            //[controller setEdgesForExtendedLayout:UIRectEdgeNone];
            //[controller setExtendedLayoutIncludesOpaqueBars:NO];
        //}
        controller.view = myview;

		x->xid = cw;
		x->w = w; w->i = x;
		x->wait_for_expose = 1;
		x->next = Fl_X::first;
		Fl_X::first = x;

        cw.rootViewController = controller;
		[cw addSubview: myview];
		//[myview release];

		if (w->size_range_set) w->size_range_();

		if (w->border() || (!w->modal() && !w->tooltip_window())) {
			Fl_Tooltip::enter(0);
		}

		if (w->modal()) Fl::modal_ = w;

		w->set_visible();
		if (w->border() || (!w->modal() && !w->tooltip_window())) Fl::handle(FL_FOCUS, w);
		Fl::first_window(w);
        [cw makeKeyAndVisible];

		int old_event = Fl::e_number;
		w->handle(Fl::e_number = FL_SHOW);
		Fl::e_number = old_event;

		// if (w->modal()) { Fl::modal_ = w; fl_fix_focus(); }
	}
}
//*/


/*
 * Tell the OS what window sizes we want to allow
 */
void Fl_Window::size_range_()
{
}


/*
 * returns pointer to the filename, or null if name ends with ':'
 */
const char* fl_filename_name(const char *name)
{
	const char *p, *q;
	if (!name) return (0);
	for (p = q = name; *p;) {
		if ((p[0] == ':') && (p[1] == ':')) {
			q = p + 2;
			p++;
		} else if (p[0] == '/') {
			q = p + 1;
		}
		p++;
	}
	return q;
}


/*
 * set the window title bar name
 */
void Fl_Window::label(const char *name, const char *mininame)
{
}


/*
 * make a window visible
 */
void Fl_Window::show()
{
	image(Fl::scheme_bg_);
	if (Fl::scheme_bg_) {
		labeltype(FL_NORMAL_LABEL);
		align(FL_ALIGN_CENTER | FL_ALIGN_INSIDE | FL_ALIGN_CLIP);
	} else {
		labeltype(FL_NO_LABEL);
	}
	Fl_Tooltip::exit(this);
	Fl_X *top = NULL;
	if (parent()) top = top_window()->flx;
	if (!shown() && (!parent() || (top))) {
		Fl_X::make(this);
	} else {
		if (!parent()) {
			/*
			if ([flx->xid isMiniaturized]) {
			    flx->w->redraw();
			    [flx->xid deminiaturize: nil];
			}
			 */
			if (!fl_capture) {
				//[flx->xid makeKeyAndOrderFront: nil];
				[flx->xid makeKeyAndVisible];
			}
		} else set_visible();
	}
	/*
	image(Fl::scheme_bg_);
	if (Fl::scheme_bg_) {
		labeltype(FL_NORMAL_LABEL);
		align(FL_ALIGN_CENTER | FL_ALIGN_INSIDE | FL_ALIGN_CLIP);
	} else {
		labeltype(FL_NO_LABEL);
	}
	Fl_Tooltip::exit(this);
	if (!shown()) {
		fl_open_display();
		//if (can_boxcheat(box())) fl_background_pixel = int(fl_xpixel(color()));
		Fl_X::make(this);
	} else {
		//printf("Fl_Window::show 2\n");
		// Once again, we would lose the capture if we activated the window.
		//if (IsIconic(i->xid)) OpenIcon(i->xid);
		//if (!fl_capture) BringWindowToTop(i->xid);
		//ShowWindow(i->xid,fl_capture?SW_SHOWNOACTIVATE:SW_RESTORE);
	}
	 */
}

/*
 * resize a window
 */
void Fl_Window::resize(int X, int Y, int W, int H)
{
	//*
	int bx, by, bt;
	Fl_Window *parent;
	if (W <= 0) W = 1; // OS X does not like zero width windows
	if (H <= 0) H = 1;
	int is_a_resize = (W != w() || H != h());
	//  printf("Fl_Window::resize(X=%d, Y=%d, W=%d, H=%d), is_a_resize=%d, resize_from_system=%p, this=%p\n",
	//         X, Y, W, H, is_a_resize, resize_from_system, this);
	if (X != x() || Y != y()) set_flag(FORCE_POSITION);
	else if (!is_a_resize) {
		resize_from_system = 0;
		return;
	}
	if ((resize_from_system != this) && shown()) {
		if (is_a_resize) {
			if (resizable()) {
				if (W < minw) minw = W; // user request for resize takes priority
				if (maxw && W > maxw) maxw = W; // over a previously set size_range
				if (H < minh) minh = H;
				if (maxh && H > maxh) maxh = H;
				size_range(minw, minh, maxw, maxh);
			} else {
				size_range(W, H, W, H);
			}
			Fl_Group::resize(X, Y, W, H);
			// transmit changes in FLTK coords to cocoa
			//get_window_frame_sizes(bx, by, bt);
			bt = 0;
			bx = X;
			by = Y;
			parent = window();
			while (parent) {
				bx += parent->x();
				by += parent->y();
				parent = parent->window();
			}
			CGRect r = CGRectMake(bx, getscreenheight() - (by + H), W, H + (border() ? bt : 0));
			if (visible_r()) {
				[Fl_X::i(this)->xid.rootViewController.view setFrame : r];
				[Fl_X::i(this)->xid setFrame : r];
			}
		} else {
			bx = X;
			by = Y;
			parent = window();
			while (parent) {
				bx += parent->x();
				by += parent->y();
				parent = parent->window();
			}
			//CGPoint pt;// = NSMakePoint(bx, main_screen_height - (by + H));
			//pt.x = bx;
			//pt.y = getscreenheight()-(by+H);
			CGRect r = CGRectMake(bx, getscreenheight() - (by + H), w(), h());
			if (visible_r()) {
				[Fl_X::i(this)->xid.rootViewController.view setFrame : r];
				[Fl_X::i(this)->xid setFrame : r]; // [fl_xid(this) setFrameOrigin:pt]; // set cocoa coords to FLTK position
			}
		}
	} else {
		resize_from_system = 0;
		if (is_a_resize) {
			Fl_Group::resize(X, Y, W, H);
			if (shown()) {
				redraw();
			}
		} else {
			x(X);
			y(Y);
		}
	}
	//*/
	/*
	if ((!parent()) && shown()) {
	    //size_range(W, H, W, H);
		//int bx, by, bt;
		//if (!this->border()) bt = 0;
		//else get_window_frame_sizes(bx, by, bt);
	    x(X); y(Y);w(W);h(H);

	    //printf("resize(), x=%d, y=%d, w=%d, h=%d\n", X, Y, W, H);
		CGRect dim;
	    dim.origin.x = X;//0.0;//X;
	    dim.origin.y = Y;//0.0;//Y;//main_screen_height - (Y + H);
		dim.size.width = W;
		dim.size.height = H;// + bt;
		//[i->xid frame: dim display: YES]; // calls windowDidResize
	    [Fl_X::i(this)->xid setFrame:dim];
	    //flx->xid.frame = dim;
	    //[i->xid setNeedsDisplay];
	    dim.origin.x = 0.0;
	    dim.origin.y = 0.0;
	    flx->xid.rootViewController.view.frame = dim;
	    [flx->xid.rootViewController.view setNeedsDisplay];
		return;
	}
	resize_from_system = 0;
	//if (is_a_resize) {
		Fl_Group::resize(X, Y, W, H);
		if (shown()) {
			redraw();
		}
	//} else {
	//	x(X); y(Y);
	//}
	 //*/
}

/*
// removes x,y,w,h rectangle from region r and returns result as a new Fl_Region
static Fl_Region MacRegionMinusRect(Fl_Region r, int x, int y, int w, int h)
{
    Fl_Region outr = (Fl_Region)malloc(sizeof(*outr));
    outr->rects = (CGRect *)malloc(4 * r->count * sizeof(CGRect));
    outr->count = 0;
    CGRect rect = fl_cgrectmake_cocoa(x, y, w, h);
    for (int i = 0; i < r->count; i++) {
        CGRect A = r->rects[i];
        CGRect test = CGRectIntersection(A, rect);
        if (CGRectIsEmpty(test)) {
            outr->rects[(outr->count)++] = A;
        } else {
            const CGFloat verylarge = 100000.;
            CGRect side = CGRectMake(0, 0, rect.origin.x, verylarge); // W side
            test = CGRectIntersection(A, side);
            if (!CGRectIsEmpty(test)) {
                outr->rects[(outr->count)++] = test;
            }
            side = CGRectMake(0, rect.origin.y + rect.size.height, verylarge, verylarge); // N side
            test = CGRectIntersection(A, side);
            if (!CGRectIsEmpty(test)) {
                outr->rects[(outr->count)++] = test;
            }
            side = CGRectMake(rect.origin.x + rect.size.width, 0, verylarge, verylarge); // E side
            test = CGRectIntersection(A, side);
            if (!CGRectIsEmpty(test)) {
                outr->rects[(outr->count)++] = test;
            }
            side = CGRectMake(0, 0, verylarge, rect.origin.y); // S side
            test = CGRectIntersection(A, side);
            if (!CGRectIsEmpty(test)) {
                outr->rects[(outr->count)++] = test;
            }
        }
    }
    if (outr->count == 0) {
        free(outr->rects);
        free(outr);
        outr = XRectangleRegion(0, 0, 0, 0);
    } else outr->rects = (CGRect *)realloc(outr->rects, outr->count * sizeof(CGRect));
    return outr;
}
 */

void Fl_Window::make_current()
{
	if (make_current_counts > 1) return;
	if (make_current_counts) make_current_counts++;
	Fl_X::q_release_context();
	fl_window = flx->xid;
	Fl_X::set_high_resolution( flx->mapped_to_retina() );
	current_ = this;

	/*
	NSGraphicsContext *nsgc;
	#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
	if (fl_mac_os_version >= 100400)
	    nsgc = [fl_window graphicsContext]; // 10.4
	else
	#endif
	    nsgc = through_Fl_X_flush ? [NSGraphicsContext currentContext] : [NSGraphicsContext graphicsContextWithWindow:fl_window];
	i->gc = (CGContextRef)[nsgc graphicsPort];
	 */
	flx->gc = (CGContextRef)UIGraphicsGetCurrentContext();

	fl_gc = flx->gc;
	CGContextSaveGState(fl_gc); // native context
	// antialiasing must be deactivated because it applies to rectangles too
	// and escapes even clipping!!!
	// it gets activated when needed (e.g., draw text)
	CGContextSetShouldAntialias(fl_gc, false);
	//CGFloat hgt = [[fl_window contentView] frame].size.height;
	//CGContextTranslateCTM(fl_gc, 0.5, hgt-0.5f);
	CGContextTranslateCTM(fl_gc, 0.5, 0.5f);
	CGContextScaleCTM(fl_gc, 1.0f, 1.0f); // now 0,0 is top-left point of the window
	// for subwindows, limit drawing to inside of parent window
	// half pixel offset is necessary for clipping as done by fl_cgrectmake_cocoa()
	if (flx->subRect()) CGContextClipToRect(fl_gc, CGRectOffset(*(flx->subRect()), -0.5, -0.5));

	// this is the context with origin at top left of (sub)window
	CGContextSaveGState(fl_gc);
#if defined(FLTK_USE_CAIRO)
	if (Fl::cairo_autolink_context()) Fl::cairo_make_current(this); // capture gc changes automatically to update the cairo context adequately
#endif
	fl_clip_region( 0 );

#if defined(FLTK_USE_CAIRO)
	// update the cairo_t context
	if (Fl::cairo_autolink_context()) Fl::cairo_make_current(this);
#endif

	/*
	if (make_current_counts > 1) return;
	if (make_current_counts) make_current_counts++;
	Fl_X::q_release_context();
	fl_window = i->xid;
	current_ = this;

	int xp = 0, yp = 0;
	Fl_Window *win = this;
	while (win) {
	    if (!win->window()) break;
	    xp += win->x();
	    yp += win->y();
	    win = (Fl_Window *)win->window();
	}
	i->gc = (CGContextRef)UIGraphicsGetCurrentContext();
	fl_gc = i->gc;
	Fl_Region fl_window_region = XRectangleRegion(0, 0, w(), h());
	if (!this->window()) {
	    for (Fl_X *cx = i->xidChildren; cx; cx = cx->xidNext) {   // clip-out all sub-windows
	        Fl_Window *cw = cx->w;
	        Fl_Region from = fl_window_region;
	        fl_window_region = MacRegionMinusRect(from, cw->x(), cw->y(), cw->w(), cw->h());
	        XDestroyRegion(from);
	    }
	}

	// antialiasing must be deactivated because it applies to rectangles too
	// and escapes even clipping!!!
	// it gets activated when needed (e.g., draw text)
	CGContextSetShouldAntialias(fl_gc, false);
	//CGFloat hgt = [[[fl_window rootViewController] view] frame].size.height;
	//CGContextTranslateCTM(fl_gc, 0.5, hgt - 0.5f);
	CGContextTranslateCTM(fl_gc, 0.5, 0.5f);
	//CGContextScaleCTM(fl_gc, 1.0f, -1.0f); // now 0,0 is top-left point of the window
	win = this;
	while (win && win->window()) { // translate to subwindow origin if this is a subwindow context
	    CGContextTranslateCTM(fl_gc, win->x(), win->y());
	    win = win->window();
	}
	//apply window's clip
	CGContextClipToRects(fl_gc, fl_window_region->rects, fl_window_region->count);
	XDestroyRegion(fl_window_region);
	// this is the context with origin at top left of (sub)window clipped out of its subwindows if any
	CGContextSaveGState(fl_gc);
	 */
}

// helper function to manage the current CGContext fl_gc
extern void fl_quartz_restore_line_style_();

// FLTK has only one global graphics state. This function copies the FLTK state into the
// current Quartz context
void Fl_X::q_fill_context()
{
	if (!fl_gc) return;
	if ( ! fl_window) { // a bitmap context
		CGFloat hgt = CGBitmapContextGetHeight(fl_gc);
        /*
		CGAffineTransform at = CGContextGetCTM(fl_gc);
		CGFloat offset = 0.5;
		if (at.a != 1 && at.a == at.d && at.b == 0 && at.c == 0) {
			hgt /= at.a;
			offset /= at.a;
		}
		CGContextTranslateCTM(fl_gc, offset, hgt-offset);
         */
        CGContextTranslateCTM(fl_gc, 0.5f, hgt-0.5f);
		CGContextScaleCTM(fl_gc, 1.0f, -1.0f); // now 0,0 is top-left point of the context
	}
	fl_color(fl_graphics_driver->color());
	fl_quartz_restore_line_style_();
}

// The only way to reset clipping to its original state is to pop the current graphics
// state and restore the global state.
void Fl_X::q_clear_clipping()
{
	if (!fl_gc) return;
	CGContextRestoreGState(fl_gc);
	CGContextSaveGState(fl_gc);
}

// Give the Quartz context back to the system
void Fl_X::q_release_context(Fl_X *x)
{
	if (x && x->gc != fl_gc) return;
	if (!fl_gc) return;
	CGContextRestoreGState(fl_gc); // KEEP IT: matches the CGContextSaveGState of make_current
	CGContextFlush(fl_gc);
	fl_gc = 0;
}

void Fl_X::q_begin_image(CGRect &rect, int cx, int cy, int w, int h)
{
	CGContextSaveGState(fl_gc);
	CGRect r2 = rect;
	r2.origin.x -= 0.5f;
	r2.origin.y -= 0.5f;
	CGContextClipToRect(fl_gc, r2);
	// move graphics context to origin of vertically reversed image
	// The 0.5 here cancels the 0.5 offset present in Quartz graphics contexts.
	// Thus, image and surface pixels are in phase if there's no scaling.
	// Below, we handle x2 and /2 scalings that occur when drawing to
	// a double-resolution bitmap, and when drawing a double-resolution bitmap to display.
	CGContextTranslateCTM(fl_gc, rect.origin.x - cx - 0.5, rect.origin.y - cy + h - 0.5);
	CGContextScaleCTM(fl_gc, 1, -1);
    /*
	CGAffineTransform at = CGContextGetCTM(fl_gc);
	if (at.a == at.d && at.b == 0 && at.c == 0) { // proportional scaling, no rotation
		// phase image with display pixels
		CGFloat deltax = 0, deltay = 0;
		if (at.a == 2) { // make .tx and .ty have even values
			deltax = (at.tx/2 - round(at.tx/2));
			deltay = (at.ty/2 - round(at.ty/2));
		} else if (at.a == 0.5) {
			if (Fl_Display_Device::high_resolution()) { // make .tx and .ty have int or half-int values
				deltax = -(at.tx*2 - round(at.tx*2));
				deltay = (at.ty*2 - round(at.ty*2));
			} else { // make .tx and .ty have integral values
				deltax = (at.tx - round(at.tx))*2;
				deltay = (at.ty - round(at.ty))*2;
			}
		}
		CGContextTranslateCTM(fl_gc, -deltax, -deltay);
	}
     */
	rect.origin.x = rect.origin.y = 0;
	rect.size.width = w;
	rect.size.height = h;
}

void Fl_X::q_end_image()
{
	CGContextRestoreGState(fl_gc);
}

////////////////////////////////////////////////////////////////
// Copy & Paste fltk implementation.
////////////////////////////////////////////////////////////////
static void convert_crlf(char *s, size_t len)
{
	// turn all \r characters into \n:
	for (size_t x = 0; x < len; x++) if (s[x] == '\r') s[x] = '\n';
}

// clipboard variables definitions :
char *fl_selection_buffer[2] = { NULL, NULL };
int fl_selection_length[2] = { 0, 0 };
static int fl_selection_buffer_length[2];

extern void fl_trigger_clipboard_notify(int source);

void fl_clipboard_notify_change()
{
	// No need to do anything here...
}

/*
static void clipboard_check(void)
{
    static NSInteger oldcount = -1;
    NSInteger newcount = [[UIPasteboard generalPasteboard] changeCount];
    if (newcount == oldcount) return;
    oldcount = newcount;
    fl_trigger_clipboard_notify(1);
}
*/

static void resize_selection_buffer(int len, int clipboard)
{
	if (len <= fl_selection_buffer_length[clipboard])
		return;
	delete[] fl_selection_buffer[clipboard];
	fl_selection_buffer[clipboard] = new char[len+100];
	fl_selection_buffer_length[clipboard] = len+100;
}

/*
 * create a selection
 * stuff: pointer to selected data
 * len: size of selected data
 * type: always "plain/text" for now
 */
void Fl::copy(const char *stuff, int len, int clipboard, const char *type)
{
	if (!stuff || len<0) return;
	if (clipboard >= 2) clipboard = 1; // Only on X11 do multiple clipboards make sense.

	resize_selection_buffer(len+1, clipboard);
	memcpy(fl_selection_buffer[clipboard], stuff, len);
	fl_selection_buffer[clipboard][len] = 0; // needed for direct paste
	fl_selection_length[clipboard] = len;
	if (clipboard) {
		if ( strlen(fl_selection_buffer[clipboard]) == 0 ) return;
		//CFDataRef text = CFDataCreate(kCFAllocatorDefault, (UInt8*)fl_selection_buffer[1], len);
		//if (text==NULL) return; // there was a pb creating the object, abort.
		UIPasteboard *clip = [UIPasteboard generalPasteboard];
		//[clip declareTypes:[NSArray arrayWithObject:UTF8_pasteboard_type] owner:nil];
		//[clip setData:(NSData*)text forType:UTF8_pasteboard_type];
		[clip setString : [NSString stringWithUTF8String : fl_selection_buffer[clipboard]]];
		//clip.string = text;
		//CFRelease(text);
	}
}

static int get_plain_text_from_clipboard(int clipboard)
{
	int length = 0;
	UIPasteboard *clip = [UIPasteboard generalPasteboard];
	NSString *data = [clip string];
	if ( data ) {
		const char *s_utf8 = [data UTF8String];
		int len = (int)strlen(s_utf8) + 1;
		resize_selection_buffer(len, clipboard);
		strcpy(fl_selection_buffer[clipboard], s_utf8);
		fl_selection_buffer[clipboard][len - 1] = 0;
		length = len - 1;
		convert_crlf(fl_selection_buffer[clipboard], len - 1); // turn all \r characters into \n:
		Fl::e_clipboard_type = Fl::clipboard_plain_text;
	}

	return length;

	/*
	NSString *found = [clip string ]; // [clip availableTypeFromArray:[NSArray arrayWithObjects:UTF8_pasteboard_type, @"public.utf16-plain-text", @"com.apple.traditional-mac-plain-text", nil]];
	if (found) {
	    NSData *data = [clip dataForType:found];
	    if (data) {
	        NSInteger len;
	        char *aux_c = NULL;
	        if (![found isEqualToString:UTF8_pasteboard_type]) {
	            NSString *auxstring;
	            auxstring = (NSString *)CFStringCreateWithBytes(NULL,
	                                                            (const UInt8*)[data bytes],
	                                                            [data length],
	                                                            [found isEqualToString:@"public.utf16-plain-text"] ? kCFStringEncodingUnicode : kCFStringEncodingMacRoman,
	                                                            false);
	            aux_c = strdup([auxstring UTF8String]);
	            [auxstring release];
	            len = strlen(aux_c) + 1;
	        }
	        else len = [data length] + 1;
	        resize_selection_buffer(len, clipboard);
	        if (![found isEqualToString:UTF8_pasteboard_type]) {
	            strcpy(fl_selection_buffer[clipboard], aux_c);
	            free(aux_c);
	        }
	        else {
	            [data getBytes:fl_selection_buffer[clipboard]];
	        }
	        fl_selection_buffer[clipboard][len - 1] = 0;
	        length = len - 1;
	        convert_crlf(fl_selection_buffer[clipboard], len - 1); // turn all \r characters into \n:
	        Fl::e_clipboard_type = Fl::clipboard_plain_text;
	    }
	}
	return length;
	 */
}

static Fl_Image* get_image_from_clipboard(Fl_Widget *receiver)
{
	// FIXIT: just copy string now, but image should be supported.
	/*
	    UIPasteboard *clip = [UIPasteboard generalPasteboard];
	    NSArray *present = [clip types]; // types in pasteboard in order of decreasing preference
	    NSArray  *possible = [NSArray arrayWithObjects:TIFF_pasteboard_type, PDF_pasteboard_type, PICT_pasteboard_type, nil];
	    NSString *found = nil;
	    NSUInteger rank;
	    for (NSUInteger i = 0; (!found) && i < [possible count]; i++) {
	        for (rank = 0; rank < [present count]; rank++) { // find first of possible types present in pasteboard
	            if ([[present objectAtIndex:rank] isEqualToString:[possible objectAtIndex:i]]) {
	                found = [present objectAtIndex:rank];
	                break;
	            }
	        }
	    }
	    if (!found) return NULL;
	    NSData *data = [clip dataForType:found];
	    if (!data) return NULL;
	    NSBitmapImageRep *bitmap = nil;
	    if ([found isEqualToString:TIFF_pasteboard_type]) {
	        bitmap = [[NSBitmapImageRep alloc] initWithData:data];
	    }
	    else if ([found isEqualToString:PDF_pasteboard_type] || [found isEqualToString:PICT_pasteboard_type]) {
	        NSImage *nsimg = [[NSImage alloc] initWithData:data];
	        [nsimg lockFocus];
	        bitmap = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, [nsimg size].width, [nsimg size].height)];
	        [nsimg unlockFocus];
	        [nsimg release];
	    }
	    if (!bitmap) return NULL;
	    int bytesPerPixel([bitmap bitsPerPixel]/8);
	    int bpr([bitmap bytesPerRow]);
	    int bpp([bitmap bytesPerPlane]);
	    int hh(bpp/bpr);
	    int ww(bpr/bytesPerPixel);
	    uchar *imagedata = new uchar[bpr * hh];
	    memcpy(imagedata, [bitmap bitmapData], bpr * hh);
	    Fl_RGB_Image *image = new Fl_RGB_Image(imagedata, ww, hh, bytesPerPixel);
	    image->alloc_array = 1;
	    [bitmap release];
	    Fl::e_clipboard_type = Fl::clipboard_image;
	    return image;
	*/
	return NULL;
}

// Call this when a "paste" operation happens:
void Fl::paste(Fl_Widget &receiver, int clipboard, const char *type)
{
	if (type[0] == 0) type = Fl::clipboard_plain_text;
	if (clipboard) {
		Fl::e_clipboard_type = "";
		if (strcmp(type, Fl::clipboard_plain_text) == 0) {
			fl_selection_length[1] = get_plain_text_from_clipboard(1);
		} else if (strcmp(type, Fl::clipboard_image) == 0) {
			Fl::e_clipboard_data = get_image_from_clipboard(&receiver);
			if (Fl::e_clipboard_data) {
				int done = receiver.handle(FL_PASTE);
				Fl::e_clipboard_type = "";
				if (done == 0) {
					delete (Fl_Image *)Fl::e_clipboard_data;
					Fl::e_clipboard_data = NULL;
				}
			}
			return;
		} else fl_selection_length[1] = 0;
	}
	Fl::e_text = fl_selection_buffer[clipboard];
	Fl::e_length = fl_selection_length[clipboard];
	if (!Fl::e_length) Fl::e_text = (char *)"";
	receiver.handle(FL_PASTE);
}

int Fl::clipboard_contains(const char *type)
{
	NSString *found = nil;
	if (strcmp(type, Fl::clipboard_plain_text) == 0) {
		found = [[UIPasteboard generalPasteboard] string];// availableTypeFromArray:[NSArray arrayWithObjects:UTF8_pasteboard_type, @"public.utf16-plain-text", @"com.apple.traditional-mac-plain-text", nil]];
	} else if (strcmp(type, Fl::clipboard_image) == 0) {
		// FIXIT: just copy string now, but image should be supported.
		found = nil;//[[UIPasteboard generalPasteboard] image ]; //availableTypeFromArray:[NSArray arrayWithObjects:TIFF_pasteboard_type, PDF_pasteboard_type, PICT_pasteboard_type, nil]];
	}
	return found != nil;
}

/*
int Fl_X::unlink(Fl_X *start)
{
    if (start) {
        Fl_X *pc = start;
        while (pc) {
            if (pc->xidNext == this) {
                pc->xidNext = xidNext;
                return 1;
            }
            if (pc->xidChildren) {
                if (pc->xidChildren == this) {
                    pc->xidChildren = xidNext;
                    return 1;
                }
                if (unlink(pc->xidChildren)) return 1;
            }
            pc = pc->xidNext;
        }
    } else {
        for (Fl_X *pc = Fl_X::first; pc; pc = pc->next) {
            if (unlink(pc)) return 1;
        }
    }
    return 0;
}

void Fl_X::relink(Fl_Window *w, Fl_Window *wp)
{
    Fl_X *x = Fl_X::i(w);
    Fl_X *p = Fl_X::i(wp);
    if (!x || !p) return;
    // first, check if 'x' is already registered as a child of 'p'
    for (Fl_X *i = p->xidChildren; i; i = i->xidNext) {
        if (i == x) return;
    }
    // now add 'x' as the first child of 'p'
    x->xidNext = p->xidChildren;
    p->xidChildren = x;
}
 */

void Fl_X::destroy()
{
	// subwindows share their xid with their parent window, so should not close it
	if (xid) {
		/*
		printf("xid autorelease start\n");
		[xid autorelease];
		printf("xid autorelease stop\n");
		 */

		/*
		[xid.rootViewController.view resignFirstResponder];
		xid.rootViewController.view.hidden = YES;

		[xid.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
		[xid.rootViewController release];
		//xid.rootViewController = nil;
		[xid resignKeyWindow];
		[xid removeFromSuperview];
		[xid release];
		 */

		/*
		[xid.rootViewController.view resignFirstResponder];
		xid.rootViewController.view.hidden = YES;
		[xid resignKeyWindow];
		xid.hidden = YES;

		[[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.001]];

		[xid.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
		//[xid.rootViewController release];
		[xid removeFromSuperview];
		[xid release];
		 */
		[xid.rootViewController.view removeFromSuperview];
		//[xid.rootViewController.view release];
		[xid removeFromSuperview];
		[xid release];

		//Fl_Window *first = Fl::first_window();
		//[fl_xid(first) makeKeyAndVisible];

		//*/

		//[xid resignKeyWindow];
		//[xid release];

		/*
		Fl_Window *first = Fl::first_window();
		[fl_xid(first) makeKeyAndVisible];
		[[[fl_xid(first) rootViewController] view] becomeFirstResponder];
		first->take_focus();
		 */
	}
	delete subRect();
}

void Fl_X::map()
{
	if (w && xid) {
		//printf("map\n");
		[xid setHidden : NO];
	}
}

void Fl_X::unmap()
{
	if (w && xid) {
		//printf("unmap\n");
		[xid setHidden : YES];
	}
}

// intersects current and x,y,w,h rectangle and returns result as a new Fl_Region
Fl_Region Fl_X::intersect_region_and_rect(Fl_Region current, int x, int y, int w, int h)
{
	if (current == NULL) return XRectangleRegion(x, y, w, h);
	CGRect r = fl_cgrectmake_cocoa(x, y, w, h);
	Fl_Region outr = (Fl_Region)malloc(sizeof(*outr));
	outr->count = current->count;
	outr->rects = (CGRect *)malloc(outr->count * sizeof(CGRect));
	int j = 0;
	for (int i = 0; i < current->count; i++) {
		CGRect test = CGRectIntersection(current->rects[i], r);
		if (!CGRectIsEmpty(test)) outr->rects[j++] = test;
	}
	if (j) {
		outr->count = j;
		outr->rects = (CGRect *)realloc(outr->rects, outr->count * sizeof(CGRect));
	} else {
		XDestroyRegion(outr);
		outr = XRectangleRegion(0, 0, 0, 0);
	}
	return outr;
}

void Fl_X::collapse()
{
	// it is for window iconic, do nothing
}

CFDataRef Fl_X::CGBitmapContextToTIFF(CGContextRef c)
{
	return (CFDataRef)0;
}

void Fl_X::set_key_window()
{
	[xid makeKeyAndVisible];
	[[[xid rootViewController] view] becomeFirstResponder];
}

int Fl::dnd()
{
	return Fl_X::dnd(0);
}

int Fl_X::dnd(int use_selection)
{
	// Mybe ios do not need dnd?
	/*
	// just support text now
	NSString *text = [NSString stringWithUTF8String:fl_selection_buffer[0]];
	//CFDataRef text = CFDataCreate(kCFAllocatorDefault, (UInt8 *)fl_selection_buffer[0], fl_selection_length[0]);
	if (!text) return false;
	NSAutoreleasePool *localPool;
	localPool = [[NSAutoreleasePool alloc] init];
	UIPasteboard *mypasteboard = [UIPasteboard generalPasteboard ];//pasteboardWithName: @"cyantree_pasteboard" create:YES];
	//[mypasteboard declareTypes:[NSArray arrayWithObject:UTF8_pasteboard_type] owner:nil];
	//[mypasteboard setData:(NSData*)text forType:UTF8_pasteboard_type];
	//CFRelease(text);
	[mypasteboard setString:text];
	Fl_Widget *w = Fl::pushed();
	Fl_Window *win = w->top_window();
	//UIView *myview = [Fl_X::i(win)->xid viewForBaselineLayout];// contentView];
	//NSEvent *theEvent = [NSApp currentEvent];

	//int width, height;
	//NSImage *image;
	if (use_selection) {
	    fl_selection_buffer[0][fl_selection_length[0]] = 0;
	    //image = imageFromText(fl_selection_buffer[0], &width, &height);
	} else {
	    //image = defaultDragImage(&width, &height);
	}

	static CGSize offset = { 0, 0 };
	CGPoint pt = [theEvent locationInWindow];
	pt.x -= width / 2;
	pt.y -= height / 2;
	[myview dragImage: image  at: pt  offset: offset
	            event: theEvent  pasteboard: mypasteboard
	           source: myview  slideBack: YES];

	if (w) {
	    int old_event = Fl::e_number;
	    w->handle(Fl::e_number = FL_RELEASE);
	    Fl::e_number = old_event;
	    Fl::pushed(0);
	}
	[localPool release];
	 */
	return true;
}

/*
static NSBitmapImageRep* rect_to_NSBitmapImageRep(Fl_Window *win, int x, int y, int w, int h)
// the returned value is autoreleased
{
    CGRect rect;
    UIView *winview = nil;
    while (win->window()) {
        x += win->x();
        y += win->y();
        win = win->window();
    }
    if (through_drawRect) {
        CGFloat epsilon = 0;
        //if (fl_mac_os_version >= 100600) epsilon = 0.5; // STR #2887
        //rect = NSMakeRect(x - epsilon, y - epsilon, w, h);
        epsilon = 0.5;
    } else {
        rect = NSMakeRect(x, win->h() - (y + h), w, h);
        // lock focus to win's view
        winview = [fl_xid(win) contentView];
        [winview lockFocus];
    }
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithFocusedViewRect: rect] autorelease];
    if (!through_drawRect) [winview unlockFocus];
    return bitmap;
}
 */

unsigned char* Fl_X::bitmap_from_window_rect(Fl_Window *win, int x, int y, int w, int h, int *bytesPerPixel)
/* Returns a capture of a rectangle of a mapped window as a pre-multiplied RGBA array of bytes.
 Alpha values are always 1 (except for the angles of a window title bar)
 so pre-multiplication can be ignored.
 *bytesPerPixel is always set to the value 4 upon return.
 delete[] the returned pointer after use
 */
{
	/*
	NSBitmapImageRep *bitmap = rect_to_NSBitmapImageRep(win, x, y, w, h);
	if (bitmap == nil) return NULL;
	*bytesPerPixel = [bitmap bitsPerPixel] / 8;
	int bpp = (int)[bitmap bytesPerPlane];
	int bpr = (int)[bitmap bytesPerRow];
	int hh = bpp / bpr; // sometimes hh = h-1 for unclear reason
	int ww = bpr / (*bytesPerPixel); // sometimes ww = w-1
	unsigned char *data = new unsigned char[w * h *  *bytesPerPixel];
	if (w == ww) {
	    memcpy(data, [bitmap bitmapData], w * hh *  *bytesPerPixel);
	} else {
	    unsigned char *p = [bitmap bitmapData];
	    unsigned char *q = data;
	    for (int i = 0; i < hh; i++) {
	        memcpy(q, p, *bytesPerPixel * ww);
	        p += bpr;
	        q += w * *bytesPerPixel;
	    }
	}
	return data;
	 */
	return NULL;
}

CGImageRef Fl_X::CGImage_from_window_rect(Fl_Window *win, int x, int y, int w, int h)
// CFRelease the returned CGImageRef after use
{
	return 0;
}

Window fl_xid(const Fl_Window *w) //ok
{
	Fl_X *temp = Fl_X::i(w);
	return temp ? temp->xid : 0;
}

// no decorated border
int Fl_Window::decorated_w() //ok
{
	return w();
}

int Fl_Window::decorated_h() //ok
{
	return h();
}

// not implentment fd function in ios
void Fl::add_fd(int n, int events, void (*cb)(int, void *), void *v) //ok
{
}

void Fl::add_fd(int fd, void (*cb)(int, void *), void *v) //ok
{
}

void Fl::remove_fd(int n, int events) //ok
{
}

void Fl::remove_fd(int n) //ok
{
}

//==============================================================================
static Fl_Window::DisplayOrientation convertOrientation(UIInterfaceOrientation orientation)
{
	switch (orientation) {
	case UIInterfaceOrientationPortrait:
		return Fl_Window::upright;
	case UIInterfaceOrientationPortraitUpsideDown:
		return Fl_Window::upsideDown;
	case UIInterfaceOrientationLandscapeLeft:
		return Fl_Window::rotatedClockwise;
	case UIInterfaceOrientationLandscapeRight:
		return Fl_Window::rotatedAntiClockwise;
	default:
		return Fl_Window::upright; // unknown orientation!
	}
	return Fl_Window::upright;
}

Fl_Window::DisplayOrientation Fl_Window::getCurrentOrientation()
{
	return convertOrientation([[UIApplication sharedApplication] statusBarOrientation]);
}

static NSUInteger getSupportedOrientations(Fl_Window *w)
{
	NSUInteger allowed = 0;

	if (w->isOrientationEnabled (Fl_Window::upright))              allowed |= UIInterfaceOrientationMaskPortrait;
	if (w->isOrientationEnabled (Fl_Window::upsideDown))           allowed |= UIInterfaceOrientationMaskPortraitUpsideDown;
	if (w->isOrientationEnabled (Fl_Window::rotatedClockwise))     allowed |= UIInterfaceOrientationMaskLandscapeLeft;
	if (w->isOrientationEnabled (Fl_Window::rotatedAntiClockwise)) allowed |= UIInterfaceOrientationMaskLandscapeRight;

	return allowed;
}

/*
static CGRect convertToCGRect (const RectType& r)
{
	return CGRectMake ((CGFloat) r.getX(), (CGFloat) r.getY(), (CGFloat) r.getWidth(), (CGFloat) r.getHeight());
}
*/

//==============================================================================
//========================== implementation ====================================
//==============================================================================
@implementation FLViewController

- (NSUInteger) supportedInterfaceOrientations
{
	//printf("supportedInterfaceOrientations\n");
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
	return getSupportedOrientations(w);
}

- (BOOL) shouldAutorotateToInterfaceOrientation : (UIInterfaceOrientation) interfaceOrientation
{
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
	return w->isOrientationEnabled (convertOrientation(interfaceOrientation));
}

- (void) willRotateToInterfaceOrientation : (UIInterfaceOrientation) toInterfaceOrientation duration : (NSTimeInterval) duration
{
	[self RotationReadyChange : nil];
	[UIView setAnimationsEnabled : YES]; // disable this because it goes the wrong way and looks like crap.
}

- (void) RotationReadyChange : (id)v
{
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
	//Fl::handle(FL_SCREEN_CONFIGURATION_READYCHANGED, w);
}
- (void) didRotateFromInterfaceOrientation : (UIInterfaceOrientation) fromInterfaceOrientation
{
	/*
	islandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
	//printf("didRotateFromInterfaceOrientation: islandscape=%d\n", islandscape);
	Fl::call_screen_init();
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
	Fl::handle(FL_SCREEN_CONFIGURATION_CHANGED, w);
	 */

	/*
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
	Fl::handle(FL_EVENT_SCREEN_ROTATION, w);
	 */
	[self RotationChange : nil];

	[UIView setAnimationsEnabled : YES];

	//[self performSelector:@selector(RotationChange:) withObject:nil afterDelay:0.0f];
}

- (void)RotationChange : (id)v
{
	islandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
	//printf("didRotateFromInterfaceOrientation: islandscape=%d\n", islandscape);
	Fl::call_screen_init();
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
	Fl::handle(FL_SCREEN_CONFIGURATION_CHANGED, w);
}

- (BOOL)prefersStatusBarHidden
{
	//printf("prefersStatusBarHidden\n");
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
	if ( w->fullscreen_active() ) return YES;
	else {
		//printf("no\n");
		return NO;
	}
}

- (void)viewDidLoad
{
	[super viewDidLoad];
}

@end

// =====================================================================
static int btkb_keysym_, btkb_state_;
static double btkb_time_sec_ = 0.5;
static void cb_time_btkb(void *data)
{
	Fl_Window *target = (Fl_Window *)data;
	Fl::e_keysym = btkb_keysym_;
	Fl::e_state = btkb_state_;
	Fl::handle(FL_KEYDOWN, target);
	//ios_reset_spot();

	btkb_time_sec_ = 0.05;
	//if ( btkb_time_sec_ <= 0.10 ) btkb_time_sec_ = 0.1;
	Fl::repeat_timeout(btkb_time_sec_, cb_time_btkb, data);
}
static void BTKB_PressContinue_Start(void *data)
{
	btkb_time_sec_ = 0.5;
	Fl::add_timeout(btkb_time_sec_, cb_time_btkb, data);
}

static void BTKB_PressContinue_Stop()
{
	//ios_reset_spot();
	Fl::remove_timeout(cb_time_btkb);
}

static char *e_text_buffer_=NULL;
static int e_text_buffer_size_=0;

// =====================================================================
// type:0-begin,1-move,2-end,3-cancel
static void iosMouseHandler(NSSet *touches, UIEvent *event, UIView *viewx, Fl_Window *winx, int type)
{
	// type:0-begin,1-move,2-end,3-cancel
	// if ( type == 3 ) return; // cancel
	Fl_Window *win = winx;

	fl_lock_function();

	if (!win->shown()) {
		fl_unlock_function();
		return;
	}

	Fl_Window *first = Fl::first_window();
	if (first != win && !(first->modal() || first->non_modal())) {
		Fl::first_window(win);
	}

	win = first;
	UIView *view = fl_xid(win).rootViewController.view;

	UITouch *touch = [touches anyObject];
	touch_tapcount_ = (int)[touch tapCount];

	int wx=win->x(), wy=win->y();
	for (Fl_Window* w = win->window(); w; w = w->window()) {
		wx += w->x();
		wy += w->y();
	}

	CGPoint pos;
	NSEnumerator *enumerator = [touches objectEnumerator];
	int i;
	if ( type == 0 ) {
		while (touch = [enumerator nextObject]) {
			for (i=0; i<MaxFinger; i++) {
				if (touch_class[i] == 0) {
					touch_class[i] = touch;
					break;
				}
			}
		}

		//for (i=0; i<MaxFinger; i++) touch_end_class[i] = 0;
	}

	if ( type > 1 ) {
		while (touch = [enumerator nextObject]) {
			for (i=0; i<MaxFinger; i++) {
				if (touch_class[i] == touch) {
					touch_class[i] = 0;
					break;
				}
			}
			for (i=0; i<MaxFinger; i++) {
				if (touch_end_class[i] == 0) {
					touch_end_class[i] = touch;
					break;
				}
			}
		}
	}

	touch_finger_ = 0;
	for (i=0; i<MaxFinger; i++) {
		if (touch_class[i] != 0) {
			touch_finger_++;
		}
	}

	int n = 0;
	for (i=0; i<MaxFinger; i++) {
		if ( touch_class[i] == 0 ) continue;
		touch = touch_class[i];
		pos = [touch locationInView : view];
		touch_x_[n] = (int)pos.x;
		touch_y_[n] = (int)pos.y;
		touch_x_root_[n] = wx + touch_x_[n];
		touch_y_root_[n] = wy + touch_y_[n];
		n++;
	}

	touch_end_finger_ = 0;
	for (i=0; i<MaxFinger; i++) {
		if (touch_end_class[i] != 0) {
			touch_end_finger_++;
		}
	}

	n = 0;
	for (i=0; i<MaxFinger; i++) {
		if ( touch_end_class[i] == 0 ) continue;
		touch = touch_end_class[i];
		pos = [touch locationInView : view];
		touch_end_x_[n] = (int)pos.x;
		touch_end_y_[n] = (int)pos.y;
		touch_end_x_root_[n] = wx + touch_x_[n];
		touch_end_y_root_[n] = wy + touch_y_[n];
		n++;
	}
	/*
	while (touch = [enumerator nextObject]) {
	    pos = [touch locationInView:view];
	    touch_x_[touch_finger_] = (int)pos.x;
	    touch_y_[touch_finger_] = (int)pos.y;
	    touch_x_root_[touch_finger_] = wx + touch_x_[touch_finger_];
	    touch_y_root_[touch_finger_] = wy + touch_y_[touch_finger_];
	    touch_finger_++;
	}
	 */

	if ( type == 0 ) {
		touch_type_ = FL_TOUCH_BEGIN;
		Fl::handle(FL_EVENT_TOUCH, win);
		touch_type_ = FL_TOUCH_NONE;
	} else if ( type == 1 ) {
		touch_type_ = FL_TOUCH_MOVE;
		Fl::handle(FL_EVENT_TOUCH, win);
		touch_type_ = FL_TOUCH_NONE;
	} else if ( type == 2 ) {
		touch_type_ = FL_TOUCH_END;
		Fl::handle(FL_EVENT_TOUCH, win);
		touch_type_ = FL_TOUCH_NONE;
		for (i=0; i<MaxFinger; i++) touch_end_class[i] = 0;
	} else if ( type == 3 ) {
		touch_type_ = FL_TOUCH_CANCEL;
		Fl::handle(FL_EVENT_TOUCH, win);
		touch_type_ = FL_TOUCH_NONE;
		for (i=0; i<MaxFinger; i++) touch_end_class[i] = 0;
	}

	if ( touch_finger_ == 1 && type == 0 ) { // begin
		Fl::e_is_click = 1;
		Fl::e_clicks = 0;
		Fl::e_state = 0;
		Fl::e_keysym = FL_Button + 1;
		Fl::e_x = touch_x_[0];
		Fl::e_y = touch_y_[0];
		Fl::e_x_root = touch_x_root_[0];
		Fl::e_y_root = touch_y_root_[0];

		mouse_simulate_by_touch_ = 1;
		Fl::handle(FL_PUSH, win);
		mouse_simulate_by_touch_ = 0;
	}

	if ( touch_finger_ == 1 && type == 1 && touch_end_finger_ == 0 ) { // move
		Fl::e_is_click = 1;
		Fl::e_clicks = 0;
		Fl::e_state = 0;
		Fl::e_keysym = FL_Button + 1;
		Fl::e_x = touch_x_[0];
		Fl::e_y = touch_y_[0];
		Fl::e_x_root = touch_x_root_[0];
		Fl::e_y_root = touch_y_root_[0];

		mouse_simulate_by_touch_ = 1;
		Fl::handle(FL_DRAG, win);
		mouse_simulate_by_touch_ = 0;
	}

	if ( touch_finger_ == 0 && type > 1 && touch_end_finger_ == 1 ) { // end and cancel
		Fl::e_is_click = 1;
		Fl::e_clicks = 0;
		Fl::e_state = 0;
		Fl::e_keysym = FL_Button + 1;
		Fl::e_x = touch_end_x_[0];
		Fl::e_y = touch_end_y_[0];
		Fl::e_x_root = touch_end_x_root_[0];
		Fl::e_y_root = touch_end_y_root_[0];
		//printf("handle release\n");
		mouse_simulate_by_touch_ = 1;
		Fl::handle(FL_RELEASE, win);
		mouse_simulate_by_touch_ = 0;
	}

	fl_unlock_function();
}

// =====================================================================
@implementation FLView

- (FLView*) initWithFlWindow : (Fl_Window*)win contentRect : (CGRect) rect;
{
	[super initWithFrame : rect];

	flwindow = win;
	in_key_event = NO;

	CGRect r;
	r.origin.x = 10;
	r.origin.y = 140;
	r.size.width = 120;
	r.size.height = 50;
	hiddenTextView = [[UITextView alloc] initWithFrame : r];
	hiddenTextView.delegate = self;
	hiddenTextView.autocapitalizationType = UITextAutocapitalizationTypeNone;
	hiddenTextView.autocorrectionType = UITextAutocorrectionTypeNo;
	hiddenTextView.keyboardType = UIKeyboardTypeDefault;
	hiddenTextView.text = @"1";
	hiddenTextView.hidden = YES;
	hiddenTextView.userInteractionEnabled = NO;
	[self addSubview : hiddenTextView];

	[[NSNotificationCenter defaultCenter] addObserver : self selector : @selector(keyboardWillShow:) name : UIKeyboardWillShowNotification object : nil];
	[[NSNotificationCenter defaultCenter] addObserver : self selector : @selector(keyboardWillHide:) name : UIKeyboardWillHideNotification object : nil];
	[[NSNotificationCenter defaultCenter] addObserver : self selector : @selector(keyboardWillChangeFrame:) name : UIKeyboardWillChangeFrameNotification object : nil];
	[[NSNotificationCenter defaultCenter] addObserver : self selector : @selector(changeInputMode:) name : UITextInputCurrentInputModeDidChangeNotification object : nil];

	return self;
}

- (Fl_Window *)getFl_Window
{
	return flwindow;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver : self name : UIKeyboardWillShowNotification object : nil];
	[[NSNotificationCenter defaultCenter] removeObserver : self name : UIKeyboardWillHideNotification object : nil];
	[[NSNotificationCenter defaultCenter] removeObserver : self name : UIKeyboardWillChangeFrameNotification object : nil];
	[[NSNotificationCenter defaultCenter] removeObserver : self name : UITextInputCurrentInputModeDidChangeNotification object : nil];

	[hiddenTextView removeFromSuperview];
	[hiddenTextView release];

	[super dealloc];
}

- (void) drawRect : (CGRect) r
{
	fl_lock_function();
	FLWindow *cw = (FLWindow*)[self window];
	Fl_Window *w = [cw getFl_Window];
	through_drawRect = YES;
	handleUpdateEvent(w);
	through_drawRect = NO;
	fl_unlock_function();
}

//==============================================================================
- (void) touchesBegan : (NSSet*) touches withEvent : (UIEvent*) event
{
	iosMouseHandler(touches, event, self, flwindow, 0);
}

- (void) touchesMoved : (NSSet*) touches withEvent : (UIEvent*) event
{
	iosMouseHandler(touches, event, self, flwindow, 1);
}

- (void) touchesEnded : (NSSet*) touches withEvent : (UIEvent*) event
{
	iosMouseHandler(touches, event, self, flwindow, 2);
}

- (void) touchesCancelled : (NSSet*) touches withEvent : (UIEvent*) event
{
	iosMouseHandler(touches, event, self, flwindow, 3);

	//[self touchesEnded: touches withEvent: event];
}

//==============================================================================
- (BOOL) becomeFirstResponder
{
	return YES;
	//if (Fl::modal_ && (Fl::modal_ != flwindow)) return NO;  // prevent the caption to be redrawn as active on click
	//  when another modal window is currently the key win
	//return !(flwindow->tooltip_window() || flwindow->menu_window() || flwindow->parent());
	//return true;
}

- (BOOL) resignFirstResponder
{
	return YES;
}

- (BOOL) canBecomeFirstResponder
{
	return YES;
	//if (Fl::modal_ && (Fl::modal_ != flwindow)) return NO;  // prevent the caption to be redrawn as active on click
	//  when another modal window is currently the key win
	//return !(flwindow->tooltip_window() || flwindow->menu_window() || flwindow->parent());

	//if ( Fl::modal_ && (Fl::modal_ != flwindow) ) return NO;
	//return !(flwindow->tooltip_window() || flwindow->menu_window());
}

- (void)textViewDidChange : (UITextView *)textView
{
	Fl_Widget *focus = Fl::focus();
	Fl_Window *wfocus = [(FLWindow *)[self window] getFl_Window];
	if (!focus) focus = wfocus;
	//[self becomeFirstResponder];

	const char *ss;// = [textView.text UTF8String];
	//int cursorPosition = textView.selectedRange.location;
	//int len = textView.selectedRange.length;

	UITextRange *SelectedRange = [textView markedTextRange];
	NSString *selectedtext = [textView textInRange : SelectedRange];
	UITextPosition *pos = [textView positionFromPosition : SelectedRange.start offset : 0];

	//printf("textViewDidChange: %s, len:%d, pos:%d, sel txt:%s\n", ss, len, cursorPosition, [selectedtext UTF8String]);

	Fl_Window *target = flwindow;
	int l;

	//如果有高亮且当前字数开始位置小于最大限制时允许输入
	if (SelectedRange && pos) {
		//NSInteger startOffset = [textView offsetFromPosition:textView.beginningOfDocument toPosition:SelectedRange.start];
		//NSInteger endOffset = [textView offsetFromPosition:textView.beginningOfDocument toPosition:SelectedRange.end];
		//NSRange offsetRange = NSMakeRange(startOffset, endOffset - startOffset);
		//printf("start:%d, end:%d, off loc:%d, off len:%d\n", startOffset, endOffset, offsetRange.location, offsetRange.length);

		ss = [selectedtext UTF8String];
		l = (int)strlen(ss);
		//printf("ss:%s, l:%d, utf8 len:%d\n", ss, l, [selectedtext length]);
		//if ( l == 0 ) return;
		if ( e_text_buffer_size_ < l+1 ) {
			void *p = realloc(e_text_buffer_, l+1);
			if ( p == NULL ) return;
			e_text_buffer_ = (char*)p;
			e_text_buffer_size_ = l+1;
		}
		Fl::e_length = l;

		memcpy(e_text_buffer_, ss, l+1);
		e_text_buffer_[l] = 0;
		Fl::e_text = e_text_buffer_;

		//printf("1.length:%d, %s, ss:[%s], l=%d\n", Fl::e_length, e_text_buffer_, ss, l);

		Fl_X::next_marked_length = l;//[selectedtext length];
		Fl::e_keysym = 0;
		Fl::handle(FL_KEYDOWN, target);
		Fl::e_length = 0;
		//Fl::compose_state = 0;
	} else {
		ss = [textView.text UTF8String];
		l = (int)strlen(ss);
		if ( l <= 0 ) {
			Fl::e_length = 0;
			Fl::e_keysym = FL_BackSpace;
			Fl::handle(FL_KEYBOARD, target);
			textView.text = @"1";
			return;
		}
		if ( l == 1 ) {
			if ( Fl_X::next_marked_length > 0 ) {
				Fl_X::next_marked_length = 1;
				Fl::e_text = "";
				Fl::e_length = 0;
				Fl::e_keysym = 0;
				Fl::handle(FL_KEYDOWN, target);
				Fl::e_length = 0;
				Fl::compose_state = 0;
				Fl_X::next_marked_length = 0;
			}
			textView.text = @"1";
			return;
		}
		if ( e_text_buffer_size_ < l ) {
			void *p = realloc(e_text_buffer_, l);
			if ( p == NULL ) {
				textView.text = @"1";
				return;
			}
			e_text_buffer_ = (char*)p;
			e_text_buffer_size_ = l;
		}
		Fl::e_length = l-1;
		//printf("2.length:%d\n", Fl::e_length);
		memcpy(e_text_buffer_, ss+1, l);
		e_text_buffer_[l-1] = 0;
		Fl::e_text = e_text_buffer_;

		if ( 0 == strcmp(e_text_buffer_, "\n") || 0 == strcmp(e_text_buffer_, "\r") || 0 == strcmp(e_text_buffer_, "\r\n") ) {
			//printf("=>send enter\n");
			Fl::e_text = "";
			Fl::e_length = 0;
			Fl::e_keysym = FL_Enter;
			Fl::handle(FL_KEYBOARD, target);
			Fl::e_length = 0;
			Fl::compose_state = 0;
			Fl_X::next_marked_length = 0;
			textView.text = @"1";
			return;
		}

		if ( 0 == strcmp(e_text_buffer_, "\t") ) {
			Fl::e_length = 0;
			Fl::e_text = "";
			Fl::e_keysym = FL_Tab;
			Fl::handle(FL_KEYBOARD, target);
			Fl::e_length = 0;
			Fl::compose_state = 0;
			Fl_X::next_marked_length = 0;
			textView.text = @"1";
			return;
		}

		Fl::e_keysym = 0;
		Fl::compose_state = 0;
		Fl_X::next_marked_length = 0;
		Fl::handle(FL_KEYDOWN, target);
		Fl::e_length = 0;
		//Fl::compose_state = 0;
		//Fl_X::next_marked_length = 0;

		//printf("=====>add string:[%s]\n", Fl::e_text);
		textView.text = @"1";
	}
}

- (void)escapeKeyPressed : (UIKeyCommand *)keyCommand
{
	//printf("esc\n");
	//UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"UIKeyCommand Demo" message:[NSString stringWithFormat:@"%@ pressed", keyCommand.input] delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
	//[alertView show];
}

- (void)keyProcess : (UIKeyCommand *)keyCommand
{
	const char *s1 = [keyCommand.input UTF8String];
	//NSLog(@"input:%@, %s\n", keyCommand.input, s1);

	Fl_Window *target = flwindow;
	//*
	if ( keyCommand.input == UIKeyInputUpArrow ) {
		Fl::e_keysym = FL_Up;
		Fl::e_state = 0;
		Fl::handle(FL_KEYDOWN, target);
		ios_reset_spot();
		btkb_keysym_ = Fl::e_keysym;
		btkb_state_ = 0;
		BTKB_PressContinue_Start((void*)target);
		return;
	}

	if ( keyCommand.input == UIKeyInputDownArrow ) {
		Fl::e_keysym = FL_Down;
		Fl::e_state = 0;
		Fl::handle(FL_KEYDOWN, target);
		ios_reset_spot();
		btkb_keysym_ = Fl::e_keysym;
		btkb_state_ = 0;
		BTKB_PressContinue_Start((void*)target);
		return;
	}

	if ( keyCommand.input == UIKeyInputLeftArrow ) {
		Fl::e_keysym = FL_Left;
		Fl::e_state = 0;
		Fl::handle(FL_KEYDOWN, target);
		ios_reset_spot();
		btkb_keysym_ = Fl::e_keysym;
		btkb_state_ = 0;
		BTKB_PressContinue_Start((void*)target);
		return;
	}

	if ( keyCommand.input == UIKeyInputRightArrow ) {
		Fl::e_keysym = FL_Right;
		Fl::e_state = 0;
		Fl::handle(FL_KEYDOWN, target);
		ios_reset_spot();
		btkb_keysym_ = Fl::e_keysym;
		btkb_state_ = 0;
		BTKB_PressContinue_Start((void*)target);
		return;
	}
	//*/

	if ( strcmp(s1, "UIKeyInputPageDown") == 0 ) {
		Fl::e_keysym = FL_Page_Down;
		Fl::e_state = 0;
		Fl::handle(FL_KEYDOWN, target);
		ios_reset_spot();
		btkb_keysym_ = Fl::e_keysym;
		btkb_state_ = 0;
		BTKB_PressContinue_Start((void*)target);
		return;
	}

	if ( strcmp(s1, "UIKeyInputPageUp") == 0 ) {
		Fl::e_keysym = FL_Page_Up;
		Fl::e_state = 0;
		Fl::handle(FL_KEYDOWN, target);
		ios_reset_spot();
		btkb_keysym_ = Fl::e_keysym;
		btkb_state_ = 0;
		BTKB_PressContinue_Start((void*)target);
		return;
	}

	if ( strcmp(s1, "UIKeyInputHome") == 0 ) {
		Fl::e_keysym = FL_Home;
		Fl::handle(FL_KEYDOWN, target);
		return;
	}

	if ( strcmp(s1, "UIKeyInputEnd") == 0 ) {
		Fl::e_keysym = FL_End;
		Fl::handle(FL_KEYDOWN, target);
		return;
	}

	if ( strcmp(s1, "UIKeyInputF1") == 0 ) {
		Fl::e_keysym = FL_F+1;
		Fl::handle(FL_KEYDOWN, target);
		return;
	}
}

// shift + left right up down pagedown pageup
- (void)key_shift_up_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Up;
	Fl::e_state = FL_SHIFT;
	Fl::handle(FL_KEYDOWN, target);
	ios_reset_spot();
	btkb_keysym_ = Fl::e_keysym;
	btkb_state_ = Fl::e_state;
	BTKB_PressContinue_Start((void*)target);
	Fl::e_state = 0;
}

- (void)key_shift_down_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Down;
	Fl::e_state = FL_SHIFT;
	Fl::handle(FL_KEYDOWN, target);
	ios_reset_spot();
	btkb_keysym_ = Fl::e_keysym;
	btkb_state_ = Fl::e_state;
	BTKB_PressContinue_Start((void*)target);
	Fl::e_state = 0;
}

- (void)key_shift_left_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Left;
	Fl::e_state = FL_SHIFT;
	Fl::handle(FL_KEYDOWN, target);
	ios_reset_spot();
	btkb_keysym_ = Fl::e_keysym;
	btkb_state_ = Fl::e_state;
	BTKB_PressContinue_Start((void*)target);
	Fl::e_state = 0;
}

- (void)key_shift_right_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Right;
	Fl::e_state = FL_SHIFT;
	Fl::handle(FL_KEYDOWN, target);
	ios_reset_spot();
	btkb_keysym_ = Fl::e_keysym;
	btkb_state_ = Fl::e_state;
	BTKB_PressContinue_Start((void*)target);
	Fl::e_state = 0;
}

- (void)key_shift_pgup_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Page_Up;
	Fl::e_state = FL_SHIFT;
	Fl::handle(FL_KEYDOWN, target);
	ios_reset_spot();
	btkb_keysym_ = Fl::e_keysym;
	btkb_state_ = Fl::e_state;
	BTKB_PressContinue_Start((void*)target);
	Fl::e_state = 0;
}

- (void)key_shift_pgdn_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Page_Down;
	Fl::e_state = FL_SHIFT;
	Fl::handle(FL_KEYDOWN, target);
	ios_reset_spot();
	btkb_keysym_ = Fl::e_keysym;
	btkb_state_ = Fl::e_state;
	BTKB_PressContinue_Start((void*)target);
	Fl::e_state = 0;
}

// esc
- (void)key_esc_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Escape;
	Fl::e_state = 0;
	Fl::handle(FL_KEYDOWN, target);
}

// ctrl a c v x z y
- (void)key_ctrl_a_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = 'a';
	Fl::e_state = FL_CTRL;
	Fl::handle(FL_KEYDOWN, target);
	Fl::e_keysym = 0;
	Fl::e_state = 0;
}

- (void)key_ctrl_c_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = 'c';
	Fl::e_state = FL_CTRL;
	Fl::handle(FL_KEYDOWN, target);
	Fl::e_keysym = 0;
	Fl::e_state = 0;
}

- (void)key_ctrl_v_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = 'v';
	Fl::e_state = FL_CTRL;
	Fl::handle(FL_KEYDOWN, target);
	Fl::e_keysym = 0;
	Fl::e_state = 0;
}

- (void)key_ctrl_x_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = 'x';
	Fl::e_state = FL_CTRL;
	Fl::handle(FL_KEYDOWN, target);
	Fl::e_keysym = 0;
	Fl::e_state = 0;
}

- (void)key_ctrl_z_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = 'z';
	Fl::e_state = FL_CTRL;
	Fl::handle(FL_KEYDOWN, target);
	Fl::e_keysym = 0;
	Fl::e_state = 0;
}

- (void)key_ctrl_y_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = 'y';
	Fl::e_state = FL_CTRL;
	Fl::handle(FL_KEYDOWN, target);
	Fl::e_keysym = 0;
	Fl::e_state = 0;
}

// ctrl + left right
- (void)key_ctrl_left_Process : (UIKeyCommand *)keyCommand
{
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Left;
	Fl::e_state = FL_CTRL;
	Fl::handle(FL_KEYDOWN, target);
	ios_reset_spot();
	btkb_keysym_ = Fl::e_keysym;
	btkb_state_ = Fl::e_state;
	BTKB_PressContinue_Start((void*)target);
	Fl::e_state = 0;
}
- (void)key_ctrl_right_Process : (UIKeyCommand *)keyCommand
{
	//printf("ctrl right\n");
	Fl_Window *target = flwindow;
	Fl::e_keysym = FL_Right;
	Fl::e_state = FL_CTRL;
	Fl::handle(FL_KEYDOWN, target);
	ios_reset_spot();
	btkb_keysym_ = Fl::e_keysym;
	btkb_state_ = Fl::e_state;
	BTKB_PressContinue_Start((void*)target);
	Fl::e_state = 0;
}

//*
- (NSArray *)keyCommands
{
	//printf("keycommand\n");

	BTKB_PressContinue_Stop();

	//const char *s1 = [UIKeyInputUpArrow UTF8String];
	//NSLog(@"input: %s\n", s1);

	UIKeyCommand *key_shift = [UIKeyCommand keyCommandWithInput : @"" modifierFlags : UIKeyModifierShift action : @selector(keyProcess:)];

	//*
	UIKeyCommand *upArrow = [UIKeyCommand keyCommandWithInput : UIKeyInputUpArrow modifierFlags : 0 action : @selector(keyProcess:)];
	UIKeyCommand *downArrow = [UIKeyCommand keyCommandWithInput : UIKeyInputDownArrow modifierFlags : 0 action : @selector(keyProcess:)];
	UIKeyCommand *leftArrow = [UIKeyCommand keyCommandWithInput : UIKeyInputLeftArrow modifierFlags : 0 action : @selector(keyProcess:)];
	UIKeyCommand *rightArrow = [UIKeyCommand keyCommandWithInput : UIKeyInputRightArrow modifierFlags : 0 action : @selector(keyProcess:)];
	//*/

	UIKeyCommand *key_home = [UIKeyCommand keyCommandWithInput : @"UIKeyInputHome" modifierFlags : 0 action : @selector(keyProcess:)];
	UIKeyCommand *key_end = [UIKeyCommand keyCommandWithInput : @"UIKeyInputEnd" modifierFlags : 0 action : @selector(keyProcess:)];
	UIKeyCommand *key_insert = [UIKeyCommand keyCommandWithInput : @"UIKeyInputIns" modifierFlags : 0 action : @selector(keyProcess:)];
	UIKeyCommand *key_f1 = [UIKeyCommand keyCommandWithInput : @"UIKeyInputDelBackward" modifierFlags : 0 action : @selector(keyProcess:)];

	//UIKeyCommand *lCmd = [UIKeyCommand keyCommandWithInput:@"\r" modifierFlags:0 action:@selector(keyProcess:)];

	UIKeyCommand *key_pgdn = [UIKeyCommand keyCommandWithInput : @"UIKeyInputPageDown" modifierFlags : 0 action : @selector(keyProcess:)];
	UIKeyCommand *key_pgup = [UIKeyCommand keyCommandWithInput : @"UIKeyInputPageUp" modifierFlags : 0 action : @selector(keyProcess:)];

	UIKeyCommand *key_shift_up = [UIKeyCommand keyCommandWithInput : UIKeyInputUpArrow modifierFlags : UIKeyModifierShift action : @selector(key_shift_up_Process:)];
	UIKeyCommand *key_shift_down = [UIKeyCommand keyCommandWithInput : UIKeyInputDownArrow modifierFlags : UIKeyModifierShift action : @selector(key_shift_down_Process:)];
	UIKeyCommand *key_shift_left = [UIKeyCommand keyCommandWithInput : UIKeyInputLeftArrow modifierFlags : UIKeyModifierShift action : @selector(key_shift_left_Process:)];
	UIKeyCommand *key_shift_right = [UIKeyCommand keyCommandWithInput : UIKeyInputRightArrow modifierFlags : UIKeyModifierShift action : @selector(key_shift_right_Process:)];
	UIKeyCommand *key_shift_pgup = [UIKeyCommand keyCommandWithInput : @"UIKeyInputPageUp" modifierFlags : UIKeyModifierShift action : @selector(key_shift_pgup_Process:)];
	UIKeyCommand *key_shift_pgdn = [UIKeyCommand keyCommandWithInput : @"UIKeyInputPageDown" modifierFlags : UIKeyModifierShift action : @selector(key_shift_pgdn_Process:)];

	UIKeyCommand *key_esc = [UIKeyCommand keyCommandWithInput : UIKeyInputEscape modifierFlags : 0 action : @selector(key_esc_Process:)];

	UIKeyCommand *key_ctrl_a = [UIKeyCommand keyCommandWithInput : @"a" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_a_Process:)];
	UIKeyCommand *key_ctrl_A = [UIKeyCommand keyCommandWithInput : @"A" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_a_Process:)];
	UIKeyCommand *key_cmd_a = [UIKeyCommand keyCommandWithInput : @"a" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_a_Process:)];
	UIKeyCommand *key_cmd_A = [UIKeyCommand keyCommandWithInput : @"A" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_a_Process:)];

	UIKeyCommand *key_ctrl_c = [UIKeyCommand keyCommandWithInput : @"c" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_c_Process:)];
	UIKeyCommand *key_ctrl_C = [UIKeyCommand keyCommandWithInput : @"C" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_c_Process:)];
	UIKeyCommand *key_cmd_c = [UIKeyCommand keyCommandWithInput : @"c" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_c_Process:)];
	UIKeyCommand *key_cmd_C = [UIKeyCommand keyCommandWithInput : @"C" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_c_Process:)];

	UIKeyCommand *key_ctrl_v = [UIKeyCommand keyCommandWithInput : @"v" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_v_Process:)];
	UIKeyCommand *key_ctrl_V = [UIKeyCommand keyCommandWithInput : @"V" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_v_Process:)];
	UIKeyCommand *key_cmd_v = [UIKeyCommand keyCommandWithInput : @"v" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_v_Process:)];
	UIKeyCommand *key_cmd_V = [UIKeyCommand keyCommandWithInput : @"V" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_v_Process:)];

	UIKeyCommand *key_ctrl_x = [UIKeyCommand keyCommandWithInput : @"x" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_x_Process:)];
	UIKeyCommand *key_ctrl_X = [UIKeyCommand keyCommandWithInput : @"X" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_x_Process:)];
	UIKeyCommand *key_cmd_x = [UIKeyCommand keyCommandWithInput : @"x" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_x_Process:)];
	UIKeyCommand *key_cmd_X = [UIKeyCommand keyCommandWithInput : @"X" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_x_Process:)];

	UIKeyCommand *key_ctrl_z = [UIKeyCommand keyCommandWithInput : @"z" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_z_Process:)];
	UIKeyCommand *key_ctrl_Z = [UIKeyCommand keyCommandWithInput : @"Z" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_z_Process:)];
	UIKeyCommand *key_cmd_z = [UIKeyCommand keyCommandWithInput : @"z" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_z_Process:)];
	UIKeyCommand *key_cmd_Z = [UIKeyCommand keyCommandWithInput : @"Z" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_z_Process:)];

	UIKeyCommand *key_ctrl_y = [UIKeyCommand keyCommandWithInput : @"y" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_y_Process:)];
	UIKeyCommand *key_ctrl_Y = [UIKeyCommand keyCommandWithInput : @"Y" modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_y_Process:)];
	UIKeyCommand *key_cmd_y = [UIKeyCommand keyCommandWithInput : @"y" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_y_Process:)];
	UIKeyCommand *key_cmd_Y = [UIKeyCommand keyCommandWithInput : @"Y" modifierFlags : UIKeyModifierCommand action : @selector(key_ctrl_y_Process:)];

	// ctrl + left right
	UIKeyCommand *key_ctrl_left = [UIKeyCommand keyCommandWithInput : UIKeyInputLeftArrow modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_left_Process:)];
	UIKeyCommand *key_ctrl_right = [UIKeyCommand keyCommandWithInput : UIKeyInputRightArrow modifierFlags : UIKeyModifierControl action : @selector(key_ctrl_right_Process:)];

	NSArray *ret;

	if ( Fl_X::next_marked_length > 0 ) {
		ret = @[key_shift
		        //,upArrow, downArrow, leftArrow, rightArrow
		        ,key_home, key_end, key_insert, key_f1
		        ,key_pgdn, key_pgup
		        ,key_shift_up, key_shift_down, key_shift_left, key_shift_right, key_shift_pgdn, key_shift_pgup
		        ,key_esc
		        ,key_ctrl_a, key_ctrl_A, key_cmd_a, key_cmd_A
		        ,key_ctrl_c, key_ctrl_C, key_cmd_c, key_cmd_C
		        ,key_ctrl_v, key_ctrl_V, key_cmd_v, key_cmd_V
		        ,key_ctrl_x, key_ctrl_X, key_cmd_x, key_cmd_X
		        ,key_ctrl_z, key_ctrl_Z, key_cmd_z, key_cmd_Z
		        ,key_ctrl_y, key_ctrl_Y, key_cmd_y, key_cmd_Y
		        ,key_ctrl_left, key_ctrl_right
		       ];
	} else {
		ret = @[key_shift
		        ,upArrow, downArrow, leftArrow, rightArrow
		        ,key_home, key_end, key_insert, key_f1
		        ,key_pgdn, key_pgup
		        ,key_shift_up, key_shift_down, key_shift_left, key_shift_right, key_shift_pgdn, key_shift_pgup
		        ,key_esc
		        ,key_ctrl_a, key_ctrl_A, key_cmd_a, key_cmd_A
		        ,key_ctrl_c, key_ctrl_C, key_cmd_c, key_cmd_C
		        ,key_ctrl_v, key_ctrl_V, key_cmd_v, key_cmd_V
		        ,key_ctrl_x, key_ctrl_X, key_cmd_x, key_cmd_X
		        ,key_ctrl_z, key_ctrl_Z, key_cmd_z, key_cmd_Z
		        ,key_ctrl_y, key_ctrl_Y, key_cmd_y, key_cmd_Y
		        ,key_ctrl_left, key_ctrl_right
		       ];
	}

	return ret;
}
//*/

/*
-(UIKeyCommand *)_keyCommandForEvent:(UIEvent *)event // UIPhysicalKeyboardEvent
{
    NSLog(@"keyCommandForEvent: %@\n\
          type = %i\n\
          keycode = %@\n\
          keydown = %@\n\n",
          event.description,
          //event.debugDescription,
          event.type,
          [event valueForKey:@"_keyCode"],
          [event valueForKey:@"_isKeyDown"]);

    return nil;//  [UIKeyCommand keyCommandWithInput:nil modifierFlags:nil action:@selector(processKeyInput:)];
}
 //*/

- (UIView *)viewWithPrefix : (NSString *)prefix inView : (UIView *)view
{
	for (UIView *subview in view.subviews) {
		if ([[subview description] hasPrefix : prefix]) {
			return subview;
		}
	}

	return nil;
}

- (void) FindKeyboard
{
	theKeyboard = nil;
	for (UIWindow* window in [UIApplication sharedApplication].windows) {
		UIView *inputSetContainer = [self viewWithPrefix : @"<UIInputSetContainerView" inView : window];
		if (inputSetContainer) {
			UIView *inputSetHost = [self viewWithPrefix : @"<UIInputSetHostView" inView : inputSetContainer];
			if (inputSetHost) {
				theKeyboard = inputSetHost;
				//return;
			}
		}
	}
}

- (void) keyboardWillShow : (NSNotification *)notification
{
	[self FindKeyboard];

	NSDictionary *userInfo = [notification userInfo];
	NSValue* aValue = [userInfo objectForKey : UIKeyboardFrameEndUserInfoKey];
	CGRect keyboardRect = [aValue CGRectValue];

	softkeyboard_x = (int)keyboardRect.origin.x;
	softkeyboard_y = (int)keyboardRect.origin.y;
	softkeyboard_w = (int)keyboardRect.size.width;
	softkeyboard_h = (int)keyboardRect.size.height;

	//printf("keyboardWillShow, keyboard rect:%d %d %d %d\n", softkeyboard_x, softkeyboard_y, softkeyboard_w, softkeyboard_h);

	softkeyboard_isshow_ = 1;
	Fl_Window *win = Fl::first_window();
	if ( win ) Fl::handle(FL_EVENT_SOFTKB_CHANGE, win);//flwindow);
}

- (void) keyboardWillHide : (NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	NSValue* aValue = [userInfo objectForKey : UIKeyboardFrameEndUserInfoKey];
	CGRect keyboardRect = [aValue CGRectValue];

	softkeyboard_x = (int)keyboardRect.origin.x;
	softkeyboard_y = (int)keyboardRect.origin.y;
	softkeyboard_w = (int)keyboardRect.size.width;
	softkeyboard_h = (int)keyboardRect.size.height;

	//printf("keyboardWillHide, keyboard rect:%d %d %d %d\n", softkeyboard_x, softkeyboard_y, softkeyboard_w, softkeyboard_h);

	if ( softkeyboard_y >= getscreenheight() ) {
		softkeyboard_isshow_ = 0;
	} else {
		[self FindKeyboard];
		softkeyboard_isshow_ = 1;
	}
	Fl_Window *win = Fl::first_window();
	if ( win ) Fl::handle(FL_EVENT_SOFTKB_CHANGE, win);
}

- (void)keyboardWillChangeFrame : (NSNotification *)notification
{
	NSDictionary *info = [notification userInfo];
	CGRect beginKeyboardRect = [[info objectForKey : UIKeyboardFrameBeginUserInfoKey] CGRectValue];
	CGRect endKeyboardRect = [[info objectForKey : UIKeyboardFrameEndUserInfoKey] CGRectValue];

	int x_begin = (int)beginKeyboardRect.origin.x;
	int y_begin = (int)beginKeyboardRect.origin.y;
	int w_begin = (int)beginKeyboardRect.size.width;
	int h_begin = (int)beginKeyboardRect.size.height;
	//printf("keyboardWillChangeFrame, begin keyboard rect:%d %d %d %d\n", x_begin, y_begin, w_begin, h_begin);

	int x_end = (int)endKeyboardRect.origin.x;
	int y_end = (int)endKeyboardRect.origin.y;
	int w_end = (int)endKeyboardRect.size.width;
	int h_end = (int)endKeyboardRect.size.height;
	//printf("keyboardWillChangeFrame, end keyboard rect:%d %d %d %d\n", x_end, y_end, w_end, h_end);

	unsigned char kb_is_hide = 1;
	if ( h_begin == 0 && h_end == 0 && w_end != 0 ) {
		softkeyboard_x = 0;
		softkeyboard_y = 0;
		softkeyboard_w = 0;
		softkeyboard_h = 0;

		kb_is_hide = 0;
	} else {
		if ( x_end == 0 && y_end == 0 && w_end == 0 && h_end == 0 ) {
			softkeyboard_x = x_begin;
			softkeyboard_y = y_begin;
			softkeyboard_w = w_begin;
			softkeyboard_h = h_begin;
		} else {
			softkeyboard_x = x_end;
			softkeyboard_y = y_end;
			softkeyboard_w = w_end;
			softkeyboard_h = h_end;
		}
	}

	if ( ! kb_is_hide ) [self FindKeyboard];

	softkeyboard_isshow_ = kb_is_hide;
	Fl_Window *win = Fl::first_window();
	if ( win ) Fl::handle(FL_EVENT_SOFTKB_CHANGE, win);//flwindow);

	[self performSelector : @selector(inputchange:) withObject : nil afterDelay : 0.5f];
}

- (void) inputchange : (id) v
{
	[self FindKeyboard];
	if ( theKeyboard == nil ) return;

	softkeyboard_x = (int)theKeyboard.frame.origin.x;
	softkeyboard_y = (int)theKeyboard.frame.origin.y;
	softkeyboard_w = (int)theKeyboard.frame.size.width;
	softkeyboard_h = (int)theKeyboard.frame.size.height;

	//printf("input change\n");

	if ( softkeyboard_y >= getscreenheight() ) {
		softkeyboard_isshow_ = 0;
	} else {
		softkeyboard_isshow_ = 1;
	}
	Fl_Window *win = Fl::first_window();
	if ( win ) Fl::handle(FL_EVENT_SOFTKB_CHANGE, win);//flwindow);
}
-(void)changeInputMode : (NSNotification *)notification
{
	[self performSelector : @selector(inputchange:) withObject : nil afterDelay : 0.5f];
}

@end

//==============================================================================
@implementation FLWindow
- (FLWindow *)initWithFlWindow : (Fl_Window *)flw contentRect : (CGRect)rect
{
	self = [super initWithFrame : rect];
	if (self) w = flw;
	return self;
}
- (Fl_Window *)getFl_Window
{
	return w;
}

- (void) becomeKeyWindow;
{
	[super becomeKeyWindow];

	[self makeKeyWindow];

	// FIXIT: save focus current uiwindow?
}

-(id)hitTest : (CGPoint)point withEvent : (UIEvent *)event
{
	if ( ! keyboard_quickclick_ ) return [super hitTest : point withEvent : event];;

	if ( theKeyboard == nil || ! softkeyboard_isshow_ ) return [super hitTest : point withEvent : event];

	int y = (int)point.y;
	if ( y >= softkeyboard_y && y<=softkeyboard_y+softkeyboard_h ) {
		theKeyboard.userInteractionEnabled = YES;
	} else {
		theKeyboard.userInteractionEnabled = NO;
	}

	return [super hitTest : point withEvent : event];
}

@end

//==============================================================================
int Fl_X::softkeyboard_isshow()
{
	return softkeyboard_isshow_;
}

void Fl_X::softkeyboard_work_area(int &X, int &Y, int &W, int &H)
{
	X = softkeyboard_x;
	Y = softkeyboard_y;
	W = softkeyboard_w;
	H = softkeyboard_h;
}

int Fl_X::mouse_simulate_by_touch()
{
	return mouse_simulate_by_touch_;
}

int Fl_X::touch_type()
{
	return touch_type_;
}

int Fl_X::touch_tapcount()
{
	return touch_tapcount_;
}

int Fl_X::touch_finger()
{
	return touch_finger_;
}

int Fl_X::touch_x(int finger)
{
	if ( finger < 0 || finger >= MaxFinger ) return 0;
	return touch_x_[finger];
}

int Fl_X::touch_y(int finger)
{
	if ( finger < 0 || finger >= MaxFinger ) return 0;
	return touch_y_[finger];
}

int Fl_X::touch_x_root(int finger)
{
	if ( finger < 0 || finger >= MaxFinger ) return 0;
	return touch_x_root_[finger];
}

int Fl_X::touch_y_root(int finger)
{
	if ( finger < 0 || finger >= MaxFinger ) return 0;
	return touch_y_root_[finger];
}

int Fl_X::touch_end_finger()
{
	return touch_end_finger_;
}

int Fl_X::touch_end_x(int finger)
{
	if ( finger < 0 || finger >= MaxFinger ) return 0;
	return touch_end_x_[finger];
}

int Fl_X::touch_end_y(int finger)
{
	if ( finger < 0 || finger >= MaxFinger ) return 0;
	return touch_end_y_[finger];
}

int Fl_X::touch_end_x_root(int finger)
{
	if ( finger < 0 || finger >= MaxFinger ) return 0;
	return touch_end_x_root_[finger];
}

int Fl_X::touch_end_y_root(int finger)
{
	if ( finger < 0 || finger >= MaxFinger ) return 0;
	return touch_end_y_root_[finger];
}

//
#if FLTK_ABI_VERSION >= 10304
static const unsigned windowDidResize_mask = 1;
#else
static const unsigned long windowDidResize_mask = 1;
#endif

bool Fl_X::in_windowDidResize()
{
#if FLTK_ABI_VERSION >= 10304
	return mapped_to_retina_ & windowDidResize_mask;
#else
	return (unsigned long)xidChildren & windowDidResize_mask;
#endif
}

void Fl_X::in_windowDidResize(bool b)
{
#if FLTK_ABI_VERSION >= 10304
	if (b) mapped_to_retina_ |= windowDidResize_mask;
	else mapped_to_retina_ &= ~windowDidResize_mask;
#else
	if (b) xidChildren = (Fl_X *)((unsigned long)xidChildren | windowDidResize_mask);
	else xidChildren = (Fl_X *)((unsigned long)xidChildren & ~windowDidResize_mask);
#endif
}

#if FLTK_ABI_VERSION >= 10304
static const unsigned mapped_mask = 2;
static const unsigned changed_mask = 4;
#else
static const unsigned long mapped_mask = 2; // sizeof(unsigned long) = sizeof(Fl_X*)
static const unsigned long changed_mask = 4;
#endif

bool Fl_X::mapped_to_retina()
{
#if FLTK_ABI_VERSION >= 10304
	return mapped_to_retina_ & mapped_mask;
#else
	return (unsigned long)xidChildren & mapped_mask;
#endif
}

void Fl_X::mapped_to_retina(bool b)
{
#if FLTK_ABI_VERSION >= 10304
	if (b) mapped_to_retina_ |= mapped_mask;
	else mapped_to_retina_ &= ~mapped_mask;
#else
	if (b) xidChildren = (Fl_X *)((unsigned long)xidChildren | mapped_mask);
	else xidChildren = (Fl_X *)((unsigned long)xidChildren & ~mapped_mask);
#endif
}

bool Fl_X::changed_resolution()
{
#if FLTK_ABI_VERSION >= 10304
	return mapped_to_retina_ & changed_mask;
#else
	return (unsigned long)xidChildren & changed_mask;
#endif
}

void Fl_X::changed_resolution(bool b)
{
#if FLTK_ABI_VERSION >= 10304
	if (b) mapped_to_retina_ |= changed_mask;
	else mapped_to_retina_ &= ~changed_mask;
#else
	if (b) xidChildren = (Fl_X *)((unsigned long)xidChildren | changed_mask);
	else xidChildren = (Fl_X *)((unsigned long)xidChildren & ~changed_mask);
#endif
}

void Fl_X::set_high_resolution(bool new_val)
{
	Fl_Display_Device::high_res_window_ = new_val;
}

void fl_open_callback(void (*cb)(const char *))
{

}

void Fl_X::setAlpha(const Fl_Window *win, const float alpha)
{
	[[Fl_X::i(win)->xid rootViewController ].view setAlpha : alpha];
}

char *ios_getcwd(char *b, int l)
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *docdir = [paths objectAtIndex : 0];
	const char *s = [docdir UTF8String];

	if ( strlen(s) >= 1024 ) {
		b[0] = 0;
		return b;
	}
	strcpy(b, s);

	//NSLog(@"document dir:%@s\n", docdir);

	return b;
}

char *ios_getworkdir(char *b, int l)
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docdir = [paths objectAtIndex : 0];
    const char *s = [docdir UTF8String];
    
    if ( strlen(s) >= 1024 ) {
        b[0] = 0;
        return b;
    }
    strcpy(b, s);
    
    //NSLog(@"document dir:%@s\n", docdir);
    
    return b;
}

static char currentlang_[128] = {0};
char *ios_getcurrentlang()
{
	// en zh-Hans
	//if ( currentlang_[0] != 0 ) return currentlang_;

	NSArray *languages = [NSLocale preferredLanguages];
	NSString *currentLanguage = [languages objectAtIndex : 0];
	const char *s = [currentLanguage UTF8String];

	if ( strlen(s) >= 128 ) {
		currentlang_[0] = 0;
		return currentlang_;
	}

	strcpy(currentlang_, s);
	return currentlang_;
}

static char appversion_[64] = {0};
char *ios_getversion()
{
	NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey : @"CFBundleShortVersionString"];
	const char *s = [version UTF8String];

	if ( strlen(s) >= 64 ) {
		appversion_[0] = 0;
		return appversion_;
	}

	strcpy(appversion_, s);
	return appversion_;
}

void ios_keyboard_quickclick(unsigned char active)
{
	keyboard_quickclick_ = active;
}

#endif // __FLTK_IPHONEOS__
