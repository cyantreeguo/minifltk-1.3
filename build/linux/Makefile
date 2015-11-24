SRCPATH = ./FL/src/
FLTK = -I./FL -I. -I/usr/include/freetype2 -lXft  -lfontconfig -lXinerama -lpthread -ldl -lm  -lX11 -lXext \
	$(SRCPATH)*.c $(SRCPATH)*.cxx

GLPATH = ./FL/extra_gl/src/
FLTK_GL = -lGL -lGLU \
		$(GLPATH)*.cxx
all:
	g++ -o demo hello.cxx $(FLTK) 
#	$(FLTK_GL)
		
clean:
	rm -rf demo *.o
