local F = require("test.sessions.fixtures")
local scan = require("vc.sessions.scan")

local function row(store, name)
	local path = store.proj .. name .. ".jsonl"
	return scan.scan_file(path, vim.uv.fs_stat(path))
end

describe("scan", function()
	local store = F.store()

	it("uses the last ai-title, project from cwd, full-conversation count", function()
		local r = row(store, "titled")
		eq("Fix flaky login test v2", r.title)
		eq("api-server", r.project)
		eq(store.alive, r.cwd)
		eq(4, r.msg_count) -- user, assistant, tool_result, assistant
		eq(scan.parse_ts("2026-11-26T10:05:00.000Z"), r.last_ts)
		eq("titled", r.id)
	end)

	it("falls back to the first prompt, stripped and one line", function()
		local r = row(store, "untitled")
		eq("hello world", r.title)
		eq("proto", r.project)
	end)

	it("lists an empty file as untitled with the dir name as project", function()
		local r = row(store, "empty")
		eq("(untitled)", r.title)
		eq(0, r.msg_count)
		eq("-proj-a", r.project)
		eq(r.mtime, r.last_ts)
	end)

	it("skips corrupt lines", function()
		local r = row(store, "corrupt")
		eq("only prompt", r.title)
	end)

	it("has no recap unless Claude Code wrote one", function()
		eq(nil, row(store, "titled").recap)
	end)

	describe("recap", function()
		local function scan_lines(lines)
			local path = tmpdir() .. "/s.jsonl"
			write_file(path, lines)
			return scan.scan_file(path, vim.uv.fs_stat(path))
		end

		it("reads the output of /recap, latest wins, on one line", function()
			local r = scan_lines({
				F.user("hi", "2026-11-26T10:00:00.000Z", "/w"),
				F.recap_command("old recap"),
				F.recap_command("You are fixing the\nlogin test.   Next: push."),
			})
			eq("You are fixing the login test. Next: push.", r.recap)
		end)

		it("reads the automatic away_summary and drops the settings hint", function()
			local r = scan_lines({
				F.user("hi", "2026-11-26T10:00:00.000Z", "/w"),
				F.system("away_summary", "Pushing main next. (disable recaps in /config)"),
			})
			eq("Pushing main next.", r.recap)
		end)

		it("ignores the output of other local commands", function()
			local r = scan_lines({
				F.user("hi", "2026-11-26T10:00:00.000Z", "/w"),
				F.system("local_command", "<local-command-stdout>Resume cancelled</local-command-stdout>", {
					commandRun = { command = "resume", args = "" },
				}),
				F.recap_command(""),
			})
			eq(nil, r.recap)
		end)
	end)

	describe("last message, branch and PR", function()
		local function scan_lines(lines)
			local path = tmpdir() .. "/s.jsonl"
			write_file(path, lines)
			return scan.scan_file(path, vim.uv.fs_stat(path))
		end
		local T = "2026-11-26T10:00:00.000Z"
		local function user(text, extra)
			return F.user(text, T, "/w", extra)
		end

		it("is the latest message the user wrote, in full, on one line", function()
			local r = scan_lines({
				F.title("Titled"),
				user("first thing"),
				F.assistant({ { type = "text", text = "ok" } }, T, "/w"),
				user("then   this\nand that"),
				F.tool_result(T, "/w"),
			})
			eq("then this and that", r.last_prompt)
		end)

		it("is nil when it would only repeat the title", function()
			local r = scan_lines({ user("only message"), F.assistant({ { type = "text", text = "ok" } }, T, "/w") })
			eq("only message", r.title)
			eq(nil, r.last_prompt)
		end)

		it("skips bare commands, compaction summaries and interruptions", function()
			local r = scan_lines({
				F.title("Titled"),
				user("the real one"),
				F.command("clear", "", T, "/w"),
				user("This session is being continued from a previous conversation.", { isCompactSummary = true }),
				user("[Request interrupted by user]"),
			})
			eq("the real one", r.last_prompt)
		end)

		it("counts a command with arguments as the arguments", function()
			local r =
				scan_lines({ F.title("Titled"), user("hello"), F.command("pm-spec", "Improve the  preview", T, "/w") })
			eq("Improve the preview", r.last_prompt)
		end)

		it("ends with an ellipsis when over 2000 characters", function()
			local r = scan_lines({ F.title("Titled"), user(string.rep("a", 2500)) })
			eq(2000, vim.fn.strchars(r.last_prompt))
			eq("…", vim.fn.strcharpart(r.last_prompt, 1999, 1))
		end)

		it("takes the branch of the last message, and none when detached", function()
			eq("feat/x", scan_lines({ user("a", { gitBranch = "main" }), user("b", { gitBranch = "feat/x" }) }).branch)
			eq(nil, scan_lines({ user("a", { gitBranch = "HEAD" }) }).branch)
			eq(nil, scan_lines({ user("a") }).branch)
		end)

		it("takes the latest pull request number", function()
			eq(8, scan_lines({ user("a"), F.pr_link(3), F.pr_link(8) }).pr)
			eq(nil, scan_lines({ user("a") }).pr)
		end)
	end)

	it("parses timestamps as UTC epoch", function()
		eq(0, scan.parse_ts("1970-01-01T00:00:00Z"))
		eq(1767225600, scan.parse_ts("2026-01-01T00:00:00.000Z"))
		eq(nil, scan.parse_ts("nope"))
	end)
end)
