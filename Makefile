PREFIX = /usr/local
BIN_PREFIX = $(DESTDIR)$(PREFIX)/bin

install:
	mkdir -p $(BIN_PREFIX)
	cp -f pq $(BIN_PREFIX)

uninstall:
	rm -f $(BIN_PREFIX)/pq

.PHONY: install uninstall
