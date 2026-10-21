.PHONY: test sanitize app-unsigned inspect-unsigned deb package-unsigned ipa clean
SHIRO_HOST_CC ?= /usr/bin/cc
test:
	env PATH=/usr/bin:/bin $(MAKE) -C tests test CC=$(SHIRO_HOST_CC)
sanitize:
	env PATH=/usr/bin:/bin $(MAKE) -C tests sanitize CC=$(SHIRO_HOST_CC)
app-unsigned:
	$(MAKE) -f scripts/ios.mk app
inspect-unsigned:
	$(MAKE) -f scripts/ios.mk inspect
ipa:
	bash scripts/package_ipa.sh
package-unsigned:
	bash scripts/package.sh --unsigned
deb:
	bash scripts/package.sh
clean:
	rm -rf build/host build/asan build/ios build/package-stage build/ipa-stage scripts/__pycache__ tests/__pycache__
