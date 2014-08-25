SRCPATH = ./minifltk-1.3/src/
FLTK = -I./minifltk-1.3 -I/usr/include/freetype2 -lXft  -lfontconfig -lXinerama -lpthread -ldl -lm  -lX11 \
	$(SRCPATH)*.c $(SRCPATH)*.cxx

GLPATH = ./minifltk-1.3/extra_gl/src/
FLTK_GL = -lGL -lGLU \
		$(GLPATH)*.cxx
all:
	g++ -o demo hello.cxx $(FLTK) 
#	$(FLTK_GL)
		
clean:
	rm -rf demo *.o
