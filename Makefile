LUAJIT ?= luajit

.PHONY: bundle

bundle:
	$(LUAJIT) loader.lua main.lua 2048.lua
