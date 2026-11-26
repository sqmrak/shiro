.PHONY: test sanitize app-unsigned inspect-unsigned deb package-unsigned ipa clean
SHIRO_HOST_CC ?= /usr/bin/cc
test:
	env PATH=/usr/bin:/bin $(MAKE) -C tests test CC=$(SHIRO_HOST_CC)
sanitize:
	env PATH=/usr/bin:/bin $(MAKE) -C tests sanitize CC=$(SHIRO_HOST_CC)
app-unsigned:
	meow build app-bundle
inspect-unsigned:
	meow build inspect
deb:
	meow build release
package-unsigned:
	meow build unsigned
ipa:
	meow build ipa
clean:
	meow clean
	rm -rf build/host build/asan build/ios build/package-stage build/ipa-stage scripts/__pycache__ tests/__pycache__
