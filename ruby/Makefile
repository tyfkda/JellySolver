
.PHONY: all
all:	build pack

.PHONY: build
build:
	bundle exec ruby tool/gen-wasm.rb build

.PHONY: pack
pack:
	bundle exec ruby tool/gen-wasm.rb pack

.PHONY: clean
clean:
	$(RM) -r build
