.PHONY: test

MINITEST = deps/mini.test

$(MINITEST):
	mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.test $(MINITEST)

test: $(MINITEST)
	nvim --headless --clean -u tests/minimal_init.lua -c "lua MiniTest.run()"
