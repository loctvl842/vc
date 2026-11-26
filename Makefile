# make test                          run every spec headless
# make test SPEC=test/sessions/scan_spec.lua
SPEC ?=
.PHONY: test lint
test:
	nvim --headless -u NONE -l test/run.lua $(SPEC)
lint:
	stylua --check lua/ test/ init.lua scripts/
