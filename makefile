DC=dmd

all:
	${DC} merda.d
	${DC} -shared -of=lib.so lib.d merda.d

