prefix ?= $(HOME)
bindir ?= $(prefix)/bin
mandir ?= $(prefix)/man
man1dir = $(mandir)/man1

INSTALL ?= install

MAN1_TXT = \
	git-send-bugzilla.txt

DOC_MAN1 = $(MAN1_TXT:.txt=.1)

.PHONY: all man1 install clean

all: man1

man1: $(DOC_MAN1)

install: man1
	$(INSTALL) -d -m755 $(DESTDIR)$(man1dir)
	$(INSTALL) -m644 $(DOC_MAN1) $(DESTDIR)$(man1dir)

clean:
	rm -f *.xml *.1 doc.dep 

%.1: %.xml
	xmlto -m callouts.xsl man $<

%.xml: %.txt
	asciidoc -b docbook -d manpage $<
