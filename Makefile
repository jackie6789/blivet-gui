PKGNAME=blivetgui
APPNAME=blivet-gui
SPECFILE=blivet-gui.spec
VERSION=$(shell awk '/Version:/ { print $$2 }' $(SPECFILE))
RELEASE=$(shell awk '/Release:/ { print $$2 }' $(SPECFILE) | sed -e 's|%.*$$||g')
RELEASE_TAG=$(VERSION)-$(RELEASE)
VERSION_TAG=$(VERSION)

ZANATA_PULL_ARGS = --transdir ./
ZANATA_PUSH_ARGS = --srcdir ./ --push-type source --force
PYTHON=python3
COVERAGE=coverage3

all:
	$(MAKE) -C po

po-pull:
	rpm -q zanata-python-client &>/dev/null || ( echo "need to run: yum install zanata-python-client"; exit 1 )
	zanata pull $(ZANATA_PULL_ARGS)

po-push: potfile
	zanata push

potfile:
	$(MAKE) -C po potfile

install-requires:
	@echo "*** Installing the dependencies required for testing and analysis ***"
	@which ansible-playbook >/dev/null 2>&1 || ( echo "Please install Ansible to install testing dependencies"; exit 1 )
	@ansible-playbook -K -i "localhost," -c local install-test-dependencies.yml

test:
	@echo "*** Running unittests ***"
	@status=0; \
	$(MAKE) gui-test || status=1; \
	$(MAKE) utils-test || status=1; \
	exit $$status

gui-test:
	@echo "*** Running GUI tests ***"
	PYTHONPATH=.:tests/ xvfb-run -s '-screen 0 640x480x8 -extension RANDR' $(PYTHON) -m unittest discover -v -s tests/blivetgui_tests -p '*_test.py'

utils-test:
	@echo "*** Running Utils tests ***"
	PYTHONPATH=.:tests/ $(PYTHON) -m unittest discover -v -s tests/blivetutils_tests -p 'test_*.py'

coverage:
	@echo "*** Running unittests with $(COVERAGE) for $(PYTHON) ***"
	PYTHONPATH=.:tests/ $(COVERAGE) run --branch -m unittest discover -v -s tests/ -p '*_test.py'
	$(COVERAGE) report --include="blivetgui/*" --show-missing

pylint:
	@echo "*** Running pylint ***"
	PYTHONPATH=. tests/pylint/runpylint.py

pep8:
	@echo "*** Running pep8 compliance check ***"
	python3-pep8 --ignore=E501,E402,E731 blivetgui/ tests/ blivet-gui blivet-gui-daemon

canary:
	$(MAKE) -C po potfile
	PYTHONPATH=translation-canary:$(PYTHONPATH) python3 -m translation_canary.translatable po/blivet-gui.pot

check:
	@status=0; \
	$(MAKE) pylint || status=1; \
	$(MAKE) pep8 || status=1; \
	$(MAKE) canary || status=1; \
	exit $$status

clean:
	-rm blivetgui/*.pyc blivetgui/*/*.pyc ChangeLog
	$(MAKE) -C po clean
	$(PYTHON) setup.py -q clean --all

install:
	$(PYTHON) setup.py install --root=$(DESTDIR)
	$(MAKE) -C po install

ChangeLog:
	(GIT_DIR=.git git log > .changelog.tmp && mv .changelog.tmp ChangeLog; rm -f .changelog.tmp) || (touch ChangeLog; echo 'git directory not found: installing possibly empty changelog.' >&2)

tag:
	@if test $(RELEASE) = "1" ; then \
	  tags='$(VERSION_TAG) $(RELEASE_TAG)' ; \
	else \
	  tags='$(RELEASE_TAG)' ; \
	fi ; \
	for tag in $$tags ; do \
	  git tag -a -m "Tag as $$tag" -f $$tag ; \
	  echo "Tagged as $$tag" ; \
	done

release: tag archive

archive: po-pull
	$(MAKE) -B ChangeLog
	git archive --format=tar --prefix=$(APPNAME)-$(VERSION)/ $(VERSION_TAG) | tar -xf -
	cp -r po $(APPNAME)-$(VERSION)
	cp ChangeLog $(APPNAME)-$(VERSION)/
	( cd $(APPNAME)-$(VERSION) && python3 setup.py -q sdist --dist-dir .. )
	rm -rf $(APPNAME)-$(VERSION)
	git checkout -- po/$(APPNAME).pot
	@echo "The archive is in $(APPNAME)-$(VERSION).tar.gz"

local: po-pull
	@make -B ChangeLog
	@python3 setup.py -q sdist --dist-dir .
	@echo "The archive is in $(APPNAME)-$(VERSION).tar.gz"

bumpver:
	@NEWSUBVER=$$((`echo $(VERSION) |cut -d . -f 3` + 1)) ; \
	NEWVERSION=`echo $(VERSION).$$NEWSUBVER |cut -d . -f 1,2,4` ; \
	DATELINE="* `LANG="en_US" date "+%a %b %d %Y"` `git config user.name` <`git config user.email`> - $$NEWVERSION-1"  ; \
	cl=`grep -n %changelog blivet-gui.spec |cut -d : -f 1` ; \
	tail --lines=+$$(($$cl + 1)) blivet-gui.spec > speclog ; \
	(head -n $$cl blivet-gui.spec ; echo "$$DATELINE" ; make --quiet rpmlog 2>/dev/null ; echo ""; cat speclog) > blivet-gui.spec.new ; \
	mv blivet-gui.spec.new blivet-gui.spec ; rm -f speclog ; \
	sed -i "s/Version: $(VERSION)/Version: $$NEWVERSION/" blivet-gui.spec ; \
	sed -i "s/version='$(VERSION)'/version='$$NEWVERSION'/" setup.py ; \
	sed -i "s/__version__\ =\ '$(VERSION)'/__version__\ =\ '$$NEWVERSION'/" blivetgui/__init__.py ; \
	sed -i "s/version\ =\ '$(VERSION)'/version\ =\ '$$NEWVERSION'/" doc/conf.py ; \
	$(MAKE) po-push

rpmlog:
	@git log --no-merges --pretty="format:- %s (%ae)" $(RELEASE_TAG).. |sed -e 's/@.*)/)/'
	@echo

srpm: local
	rpmbuild -bs --nodeps $(APPNAME).spec --define "_sourcedir `pwd`"
	rm -f $(APPNAME)-$(VERSION).tar.gz

rpm: local
	rpmbuild -bb --nodeps $(APPNAME).spec --define "_sourcedir `pwd`"
	rm -f $(APPNAME)-$(VERSION).tar.gz

ci: check test

.PHONY: check pep8 pylint clean install tag archive local
