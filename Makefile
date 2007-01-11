prefix ?= $(HOME)

bindir ?= $(prefix)/bin

INSTALL ?= install

ifndef PERL_PATH
	PERL_PATH = /usr/bin/perl
endif
export PERL_PATH

PERL_SCRIPTS = \
	git-send-bugzilla

SCRIPTS = $(PERL_SCRIPTS:.pl=)

.PHONY: all install clean doc

all: $(SCRIPTS)

install: all
	$(INSTALL) -d -m755 $(DESTDIR)$(bindir)
	$(INSTALL) $(SCRIPTS) $(DESTDIR)$(bindir)

clean:
	rm -f $(SCRIPTS)
	$(MAKE) -C docs/ clean

doc:
	$(MAKE) -C docs all

$(PERL_SCRIPTS:.pl=): %: %.pl
	rm -f $@ $@+
	sed -e 's|#!.*perl|#!$(PERL_PATH)|' $< > $@+
	chmod +x $@+
	mv $@+ $@

