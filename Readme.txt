2014-09-09 cyantree
添加linux下的trayicon控件，偶然会出现无法显示icon的问题，另外当有子窗口出现时icon无法操作，待修复

===================
2014-08-27 cyantree
修正Fl_ComboBox.h的一个错误，错把delete写成了free，会导致gcc编译时出错

===================
2014-08-27 cyantree
官方添加Fl_Shaped_Window，同步更新

===================
2014-08-26 cyantree
移植到windows mobile 5/6，vs2008编译方式：创建smart app，加入src下所有代码(不含子目录)，将minifltk-1.3目录加入搜索路径，link:Ws2.lib Ceshell.lib Commdlg.lib
已知bug:
1.fl_open未实现
2.src/os/wince/Fl_Native_File_Chooser.cxx里的SHBrowseForFolder未修改完成，具体修改方法已经写在代码里
3.输入法切换的功能有问题，会导致在中文模拟器下卡顿，估计是输入法的API使用不当，因为使用的是win32版本API，可能有不兼容

===================
2014-08-25 cyantree
将所有cxxprivate文件移入src/os，同时开始尝试移植wince平台

===================
2014-08-24 cyantree
  加入Fl_ComboBox和Fl_Win32_TrayIcon(目前只能运行在win32平台下)
  
========================================

2014-07-10 cyantree
  初步移植到ios，目前只能执行一张splash image

2014-07-06
  cyantree
  将和平台相关的代码后缀加上private，这样只要导入所有.cxx文件即可，无需再删除Platform开头的文件
  
====================================================================

windows下用vs2008编译：
添加minifltk下所有的.cxx文件，去掉platform_xxx.cxx，将minifltk加入搜索路径

osx下用xcode编译：
添加minifltk下所有.cxx cocoaXXX.mm文件，去掉platform_xxx.cxx，将minifltk加入搜索路径，将build settings下面的Objective-C automatic reference counting改成No，若要编译opengl，添加2个库：AGL和opengl

2014.05.10
内置了jpeg和png库，不再需要附带第三方库

若需要修改windows下程序的图标，添加vs_res.h和vs_res.rc，并修改app.ico

修正ImageGIF，可以使用动画

若需要使用GLWindow，添加extra_gl目录，并添加相应的库，在windows下添加opengl32.lib和glu32.lib

删除style.h和style.cxx，因为style和scheme有重复，而且造成类的结构不够清晰，但是目前scheme还不能及时更换

添加flsleep，编辑器添加行号

用codeblock编译，windows平台，和vs基本一样，除了要link2个库：libuuid.a和libole32.a

linux下用gcc编译：
参看os/linux/Makefile，在linux下必须有x11和xft(x freetype library)

===================================================================

将gl分离为extra