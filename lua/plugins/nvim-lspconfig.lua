require("lz.n").load({
	"nvim-lspconfig",

	event = { "BufReadPre", "BufNewFile" },

	load = function(name)
		vim.cmd.packadd(name)
		vim.cmd.packadd("blink.cmp")
		-- vim.cmd.packadd("lspsaga.nvim")
	end,

	after = function()
		local lspconfig = require("lspconfig")

		local signs = {
			Error = "󰅚 ",
			Warn = " ",
			Info = " ",
			Hint = "󰌶 ",
		}

		for type, icon in pairs(signs) do
			local hl = "DiagnosticSign" .. type
			vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
		end

		vim.diagnostic.config({
			signs = true,
			update_in_insert = true,
			underline = true,
			severity_sort = true,

			virtual_text = {
				prefix = "",
				format = function(diagnostic)
					local severity = diagnostic.severity

					local function prefix_diagnostic(prefix, value)
						return string.format(prefix .. " %s", value.message)
					end

					if severity == vim.diagnostic.severity.ERROR then
						return prefix_diagnostic("󰅚", diagnostic)
					end

					if severity == vim.diagnostic.severity.WARN then
						return prefix_diagnostic("⚠", diagnostic)
					end

					if severity == vim.diagnostic.severity.INFO then
						return prefix_diagnostic("ⓘ", diagnostic)
					end

					if severity == vim.diagnostic.severity.HINT then
						return prefix_diagnostic("󰌶", diagnostic)
					end

					return prefix_diagnostic("●", diagnostic)
				end,
			},
		})

		-- LSP servers and clients are able to communicate to each other what features they support.
		--  By default, Neovim doesn't support everything that is in the LSP specification.
		--  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
		--  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
		local capabilities = vim.lsp.protocol.make_client_capabilities()
		capabilities = vim.tbl_deep_extend("force", capabilities, require("blink.cmp").get_lsp_capabilities())

		local servers = {
			clangd = {
				filetypes = { "c", "cpp", "objc", "objcpp", "cuda", "proto" },
				keys = {
					{ "<leader>cR", "<cmd>ClangdSwitchSourceHeader<cr>", desc = "Switch Source/Header (C/C++)" },
				},
				on_attach = function()
					require("clangd_extensions").setup({
						inlay_hints = {
							inline = vim.fn.has("nvim-0.10") == 1,
							-- Options other than `highlight' and `priority' only work
							-- if `inline' is disabled
							-- Only show inlay hints for the current line
							only_current_line = false,
							-- Event which triggers a refresh of the inlay hints.
							-- You can make this { "CursorMoved" } or { "CursorMoved,CursorMovedI" } but
							-- note that this may cause higher CPU usage.
							-- This option is only respected when only_current_line is true.
							only_current_line_autocmd = { "CursorHold" },
							-- whether to show parameter hints with the inlay hints or not
							show_parameter_hints = true,
							-- prefix for parameter hints
							parameter_hints_prefix = "<- ",
							-- prefix for all the other hints (type, chaining)
							other_hints_prefix = "=> ",
							-- whether to align to the length of the longest line in the file
							max_len_align = false,
							-- padding from the left if max_len_align is true
							max_len_align_padding = 1,
							-- whether to align to the extreme right or not
							right_align = false,
							-- padding from the right if right_align is true
							right_align_padding = 7,
							-- The color of the hints
							highlight = "Comment",
							-- The highlight group priority for extmark
							priority = 100,
						},
						ast = {
							-- These are unicode, should be available in any font
							role_icons = {
								type = "",
								declaration = "",
								expression = "",
								specifier = "",
								statement = "",
								["template argument"] = "",
							},
							kind_icons = {
								Compound = "",
								Recovery = "",
								TranslationUnit = "",
								PackExpansion = "",
								TemplateTypeParm = "",
								TemplateTemplateParm = "",
								TemplateParamObject = "",
							},
							--[[ These require codicons (https://github.com/microsoft/vscode-codicons)
            role_icons = {
                type = "",
                declaration = "",
                expression = "",
                specifier = "",
                statement = "",
                ["template argument"] = "",
            },

            kind_icons = {
                Compound = "",
                Recovery = "",
                TranslationUnit = "",
                PackExpansion = "",
                TemplateTypeParm = "",
                TemplateTemplateParm = "",
                TemplateParamObject = "",
            }, ]]

							highlights = {
								detail = "Comment",
							},
						},
						memory_usage = {
							border = "none",
						},
						symbol_info = {
							border = "none",
						},
					})
				end,

				root_dir = function(fname)
					return require("lspconfig.util").root_pattern(
						".clangd",
						".clang-tidy",
						".clang-format",
						"Makefile",
						"configure.ac",
						"configure.in",
						"config.h.in",
						"meson.build",
						"meson_options.txt",
						"build.ninja"
					)(fname) or require("lspconfig.util").root_pattern(
						"compile_commands.json",
						"compile_flags.txt"
					)(fname) or require("lspconfig.util").find_git_ancestor(fname)
				end,

				capabilities = {
					offsetEncoding = { "utf-16" },
				},

				cmd = {
					"clangd",
					"--j=12",
					"--background-index",
					"--clang-tidy",
					"--header-insertion=iwyu",
					"--completion-style=detailed",
					"--function-arg-placeholders",
					"--fallback-style=llvm",
				},

				init_options = {
					usePlaceholders = true,
					completeUnimported = true,
					clangdFileStatus = true,
				},
			},

			pyright = {},
			rust_analyzer = {},

			lua_ls = {
				settings = {
					Lua = {
						runtime = {
							version = "LuaJIT",
						},

						completion = {
							callSnippet = "Replace",
						},

						telemetry = {
							enable = false,
						},

						hint = {
							enable = true,
						},
					},
				},
			},
		}

		for name, config in pairs(servers) do
			config.capabilities = vim.tbl_deep_extend("force", {}, capabilities, config.capabilities or {})
			lspconfig[name].setup(config)
		end
	end,
})
