-- vimki.nvim
-- A Neovim plugin for practicing Anki decks in Vim

local M = {}
local api = vim.api
local fn = vim.fn

-- Plugin state
local state = {
	current_deck = nil,
	current_card = nil,
	cards = {},
	card_index = 1,
	session_stats = {
		total = 0,
		correct = 0,
		incorrect = 0,
		skipped = 0,
	},
	anki_connect_url = "http://localhost:8765",
	anki_media_dir = nil,
	buf = nil,
	win = nil,
	image_cache = {},
	terminal_type = nil,
	practice_mode = true,
	user_answer = "",
	answer_buf = nil,
	answer_win = nil,
}

-- AnkiConnect API functions
local function anki_request(action, params)
	local data = vim.json.encode({
		action = action,
		version = 6,
		params = params or {},
	})

	local response = fn.system({
		"curl",
		"-s",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-d",
		data,
		state.anki_connect_url,
	})

	local ok, result = pcall(vim.json.decode, response)
	if not ok then
		return nil, "Failed to parse AnkiConnect response"
	end

	if result.error then
		return nil, result.error
	end

	return result.result, nil
end

-- Get list of available decks
local function get_decks()
	return anki_request("deckNames")
end

-- Get cards from a deck
local function get_cards(deck_name)
	local query = string.format('deck:"%s" is:due', deck_name)
	return anki_request("findCards", { query = query })
end

-- Get card info
local function get_card_info(card_id)
	local info, err = anki_request("cardsInfo", { cards = { card_id } })
	if err or not info or #info == 0 then
		return nil, err or "No card info found"
	end
	return info[1], nil
end

-- Answer a card
local function answer_card(card_id, ease)
	return anki_request("answerCards", {
		answers = { {
			cardId = card_id,
			ease = ease,
		} },
	})
end

-- Detect terminal type with image support
local function detect_terminal()
	if state.terminal_type then
		return state.terminal_type
	end

	local term = os.getenv("TERM")
	local term_program = os.getenv("TERM_PROGRAM")
	local kitty_pid = os.getenv("KITTY_PID")
	local wezterm = os.getenv("WEZTERM_EXECUTABLE")

	if (term and term:match("kitty")) or (kitty_pid ~= nil) then
		state.terminal_type = "kitty"
	elseif wezterm ~= nil then
		state.terminal_type = "wezterm"
	elseif term_program == "iTerm.app" then
		state.terminal_type = "iterm2"
	else
		state.terminal_type = "unsupported"
	end

	return state.terminal_type
end

-- Check if terminal supports images
local function supports_images()
	local term_type = detect_terminal()
	return term_type == "kitty" or term_type == "wezterm" or term_type == "iterm2"
end

-- Get Anki media directory
local function get_anki_media_dir()
	if state.anki_media_dir then
		return state.anki_media_dir
	end

	-- Try to get from AnkiConnect
	local result, err = anki_request("getMediaDirPath")
	if result then
		state.anki_media_dir = result
		return result
	end

	-- Fallback to common locations
	local home = os.getenv("HOME")
	local possible_paths = {
		home .. "/.local/share/Anki2/User 1/collection.media",
		home .. "/Documents/Anki/User 1/collection.media",
		home .. "/Library/Application Support/Anki2/User 1/collection.media",
	}

	for _, path in ipairs(possible_paths) do
		if fn.isdirectory(path) == 1 then
			state.anki_media_dir = path
			return path
		end
	end

	return nil
end

-- Display image using appropriate terminal protocol
local function display_image(image_path, row)
	local term_type = detect_terminal()

	if term_type == "kitty" then
		return display_kitty_image(image_path, row)
	elseif term_type == "wezterm" or term_type == "iterm2" then
		return display_iterm2_image(image_path, row)
	else
		return row + 1
	end
end

-- Display image using iTerm2/WezTerm protocol
local function display_iterm2_image(image_path, row)
	-- Check if image exists
	if fn.filereadable(image_path) == 0 then
		return row + 1
	end

	-- Get image dimensions
	local identify_cmd = string.format("identify -format '%%w %%h' '%s' 2>/dev/null", image_path)
	local dimensions = fn.system(identify_cmd)
	local width, height = dimensions:match("(%d+) (%d+)")

	if not width or not height then
		return row + 1
	end

	width = tonumber(width)
	height = tonumber(height)

	-- Calculate display size (max width: 60 chars, maintain aspect ratio)
	local max_width = 60
	local char_width = 8 -- approximate pixel width of a character
	local display_width = math.min(width, max_width * char_width)
	local display_height = math.floor(height * (display_width / width))

	-- Read and encode image
	local base64_cmd = string.format("base64 -w 0 '%s' 2>/dev/null", image_path)
	local base64_data = fn.system(base64_cmd)

	if base64_data and #base64_data > 0 then
		-- Position cursor
		io.write(string.format("\x1b[%d;1H", row))

		-- iTerm2 protocol: ESC ] 1337 ; File = [args] : base64 BEL
		local args =
			string.format("inline=1;width=%dpx;height=%dpx;preserveAspectRatio=1", display_width, display_height)
		io.write(string.format("\x1b]1337;File=%s:%s\x07", args, base64_data))

		-- Calculate how many rows the image takes
		local rows_used = math.ceil(display_height / 16) -- approximate line height
		return row + rows_used + 1
	end

	return row + 1
end

-- Display image using Kitty protocol
local function display_kitty_image(image_path, row)
	-- Check if image exists
	if fn.filereadable(image_path) == 0 then
		return row + 1
	end

	-- Clear any previous image at this position
	io.write("\x1b_Ga=d,d=I\x1b\\")

	-- Get image dimensions
	local identify_cmd = string.format("identify -format '%%w %%h' '%s' 2>/dev/null", image_path)
	local dimensions = fn.system(identify_cmd)
	local width, height = dimensions:match("(%d+) (%d+)")

	if not width or not height then
		return row + 1
	end

	width = tonumber(width)
	height = tonumber(height)

	-- Calculate display size (max width: 60 chars, maintain aspect ratio)
	local max_width = 60
	local char_width = 8 -- approximate pixel width of a character
	local display_width = math.min(width, max_width * char_width)
	local display_height = math.floor(height * (display_width / width))

	-- Encode image
	local base64_cmd = string.format("base64 -w 0 '%s'", image_path)
	local base64_data = fn.system(base64_cmd)

	if base64_data and #base64_data > 0 then
		-- Position cursor
		io.write(string.format("\x1b[%d;1H", row))

		-- Send image data in chunks
		local chunk_size = 4096
		local id = math.random(1000000)

		for i = 1, #base64_data, chunk_size do
			local chunk = base64_data:sub(i, i + chunk_size - 1)
			local is_last_chunk = i + chunk_size > #base64_data

			if i == 1 then
				-- First chunk with metadata
				io.write(
					string.format(
						"\x1b_Gi=%d,a=T,f=100,t=f,s=%d,v=%d,m=%d;%s\x1b\\",
						id,
						display_width,
						display_height,
						is_last_chunk and 0 or 1,
						chunk
					)
				)
			else
				-- Subsequent chunks
				io.write(string.format("\x1b_Gi=%d,m=%d;%s\x1b\\", id, is_last_chunk and 0 or 1, chunk))
			end
		end

		-- Calculate how many rows the image takes
		local rows_used = math.ceil(display_height / 16) -- approximate line height
		return row + rows_used + 1
	end

	return row + 1
end

-- Extract and process images from HTML content
local function process_html_content(html, start_row)
	local media_dir = get_anki_media_dir()
	if not media_dir or not supports_images() then
		-- Just strip HTML if we can't display images
		return html:gsub("<[^>]+>", ""), start_row
	end

	local processed_text = ""
	local current_row = start_row
	local last_pos = 1

	-- Find all img tags
	for img_start, img_tag, img_end in html:gmatch("()(<img[^>]+>)()") do
		-- Add text before the image
		local text_before = html:sub(last_pos, img_start - 1):gsub("<[^>]+>", "")
		if text_before ~= "" then
			processed_text = processed_text .. text_before .. "\n"
			current_row = current_row + select(2, text_before:gsub("\n", "\n")) + 1
		end

		-- Extract image source
		local src = img_tag:match('src="([^"]+)"') or img_tag:match("src='([^']+)'")
		if src then
			-- Handle Anki media files
			local image_path = media_dir .. "/" .. src

			-- Add placeholder for image
			processed_text = processed_text .. "[Image: " .. src .. "]\n"
			current_row = current_row + 1

			-- Schedule image display after buffer is rendered
			vim.schedule(function()
				display_image(image_path, current_row - 1)
			end)

			-- Reserve space for the image
			local image_lines = 10 -- Reserve some lines for the image
			for i = 1, image_lines do
				processed_text = processed_text .. "\n"
			end
			current_row = current_row + image_lines
		end

		last_pos = img_end
	end

	-- Add remaining text
	local remaining_text = html:sub(last_pos):gsub("<[^>]+>", "")
	if remaining_text ~= "" then
		processed_text = processed_text .. remaining_text
	end

	return processed_text, current_row
end

-- Clear all images
local function clear_images()
	local term_type = detect_terminal()
	if term_type == "kitty" then
		io.write("\x1b_Ga=d\x1b\\")
		-- Note: iTerm2/WezTerm don't have a universal clear command
		-- Images will be cleared when the terminal scrolls or redraws
	end
end
local function create_buffer()
	if state.buf and api.nvim_buf_is_valid(state.buf) then
		return state.buf
	end

	state.buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(state.buf, "filetype", "vimki")
	api.nvim_buf_set_option(state.buf, "buftype", "nofile")
	api.nvim_buf_set_option(state.buf, "modifiable", false)

	-- Set keymaps
	local opts = { noremap = true, silent = true }
	api.nvim_buf_set_keymap(state.buf, "n", "q", ':lua require("vimki").close()<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "<Space>", ':lua require("vimki").show_answer()<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "a", ':lua require("vimki").open_answer_input()<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "1", ':lua require("vimki").rate_card(1)<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "2", ':lua require("vimki").rate_card(2)<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "3", ':lua require("vimki").rate_card(3)<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "4", ':lua require("vimki").rate_card(4)<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "s", ':lua require("vimki").skip_card()<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "r", ':lua require("vimki").restart_session()<CR>', opts)
	api.nvim_buf_set_keymap(state.buf, "n", "p", ':lua require("vimki").toggle_practice_mode()<CR>', opts)

	return state.buf
end

local function create_window()
	local buf = create_buffer()

	-- Calculate window size
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Anki Practice ",
		title_pos = "center",
	}

	state.win = api.nvim_open_win(buf, true, opts)
	api.nvim_win_set_option(state.win, "wrap", true)
	api.nvim_win_set_option(state.win, "linebreak", true)
end

local function render_card()
	if not state.current_card then
		return
	end

	-- Clear any existing images first
	clear_images()

	api.nvim_buf_set_option(state.buf, "modifiable", true)

	local lines = {}
	table.insert(
		lines,
		"═══════════════════════════════════════════════════════"
	)
	table.insert(lines, string.format("  Deck: %s", state.current_deck))
	table.insert(lines, string.format("  Card: %d/%d", state.card_index, #state.cards))
	table.insert(
		lines,
		string.format(
			"  Session: ✓ %d  ✗ %d  → %d",
			state.session_stats.correct,
			state.session_stats.incorrect,
			state.session_stats.skipped
		)
	)
	table.insert(lines, string.format("  Mode: %s", state.practice_mode and "Practice" or "Review"))
	table.insert(
		lines,
		"═══════════════════════════════════════════════════════"
	)
	table.insert(lines, "")
	table.insert(lines, "QUESTION:")
	table.insert(lines, "─────────")

	-- Process question with image support
	local question = state.current_card.fields[state.current_card.modelName .. "-Front"].value
	local processed_question, next_row = process_html_content(question, 10)
	for line in processed_question:gmatch("[^\r\n]*") do
		if line ~= "" then
			table.insert(lines, line)
		end
	end

	table.insert(lines, "")
	table.insert(lines, "")

	if state.practice_mode and not state.show_answer then
		-- Show user's answer if they've typed one
		if state.user_answer ~= "" then
			table.insert(lines, "YOUR ANSWER:")
			table.insert(lines, "────────────")
			for line in state.user_answer:gmatch("[^\r\n]+") do
				table.insert(lines, "  " .. line)
			end
			table.insert(lines, "")
		end

		table.insert(lines, "Press [a] to type your answer, [Space] to reveal answer")
	elseif state.show_answer then
		-- Show user's answer if in practice mode
		if state.practice_mode and state.user_answer ~= "" then
			table.insert(lines, "YOUR ANSWER:")
			table.insert(lines, "────────────")
			for line in state.user_answer:gmatch("[^\r\n]+") do
				table.insert(lines, "  " .. line)
			end
			table.insert(lines, "")
		end

		table.insert(lines, "CORRECT ANSWER:")
		table.insert(lines, "───────────────")

		-- Process answer with image support
		local answer = state.current_card.fields[state.current_card.modelName .. "-Back"].value
		local answer_start_row = #lines + 1
		local processed_answer, _ = process_html_content(answer, answer_start_row)
		for line in processed_answer:gmatch("[^\r\n]*") do
			if line ~= "" then
				table.insert(lines, line)
			end
		end

		table.insert(lines, "")
		table.insert(lines, "")
		table.insert(lines, "Rate: [1] Again  [2] Hard  [3] Good  [4] Easy  [s] Skip")
	else
		table.insert(lines, "Press [Space] to show answer")
	end

	table.insert(lines, "")
	table.insert(
		lines,
		"═══════════════════════════════════════════════════════"
	)
	table.insert(lines, "[q] Quit  [r] Restart  [p] Toggle practice mode")

	api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	api.nvim_buf_set_option(state.buf, "modifiable", false)

	-- Force redraw to ensure images are displayed
	vim.cmd("redraw!")
end

local function load_next_card()
	if state.card_index > #state.cards then
		-- Session complete
		api.nvim_buf_set_option(state.buf, "modifiable", true)
		local lines = {
			"═══════════════════════════════════════════════════════",
			"  SESSION COMPLETE!",
			"═══════════════════════════════════════════════════════",
			"",
			string.format("  Total cards: %d", state.session_stats.total),
			string.format(
				"  Correct: %d (%.1f%%)",
				state.session_stats.correct,
				state.session_stats.total > 0 and (state.session_stats.correct / state.session_stats.total * 100) or 0
			),
			string.format("  Incorrect: %d", state.session_stats.incorrect),
			string.format("  Skipped: %d", state.session_stats.skipped),
			"",
			"═══════════════════════════════════════════════════════",
			"",
			"[q] Quit  [r] Start new session",
		}
		api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
		api.nvim_buf_set_option(state.buf, "modifiable", false)
		return
	end

	local card_id = state.cards[state.card_index]
	local card_info, err = get_card_info(card_id)

	if err then
		vim.notify("Failed to load card: " .. err, vim.log.levels.ERROR)
		state.card_index = state.card_index + 1
		load_next_card()
		return
	end

	state.current_card = card_info
	state.show_answer = false
	state.user_answer = ""
	render_card()
end

-- Public functions
function M.setup(opts)
	opts = opts or {}
	if opts.anki_connect_url then
		state.anki_connect_url = opts.anki_connect_url
	end
	if opts.anki_media_dir then
		state.anki_media_dir = opts.anki_media_dir
	end
	if opts.practice_mode ~= nil then
		state.practice_mode = opts.practice_mode
	end

	-- Check terminal support on setup
	local term_type = detect_terminal()
	if supports_images() then
		vim.notify(
			string.format("%s terminal detected - image support enabled!", term_type:gsub("^%l", string.upper)),
			vim.log.levels.INFO
		)
	end
end

function M.start()
	-- Check AnkiConnect
	local decks, err = get_decks()
	if err then
		vim.notify(
			"Failed to connect to AnkiConnect. Make sure Anki is running with AnkiConnect addon.",
			vim.log.levels.ERROR
		)
		return
	end

	if not decks or #decks == 0 then
		vim.notify("No decks found in Anki", vim.log.levels.WARN)
		return
	end

	-- Select deck
	vim.ui.select(decks, {
		prompt = "Select deck to practice:",
	}, function(choice)
		if not choice then
			return
		end

		state.current_deck = choice

		-- Get cards
		local cards, err = get_cards(choice)
		if err then
			vim.notify("Failed to get cards: " .. err, vim.log.levels.ERROR)
			return
		end

		if not cards or #cards == 0 then
			vim.notify("No due cards in deck: " .. choice, vim.log.levels.INFO)
			return
		end

		-- Initialize session
		state.cards = cards
		state.card_index = 1
		state.session_stats = {
			total = #cards,
			correct = 0,
			incorrect = 0,
			skipped = 0,
		}

		-- Create UI
		create_window()
		load_next_card()
	end)
end

function M.close()
	if state.win and api.nvim_win_is_valid(state.win) then
		-- Clear images before closing
		clear_images()
		api.nvim_win_close(state.win, true)
	end
	if state.answer_win and api.nvim_win_is_valid(state.answer_win) then
		api.nvim_win_close(state.answer_win, true)
	end
	state.win = nil
	state.answer_win = nil
end

function M.open_answer_input()
	if not state.current_card or state.show_answer or not state.practice_mode then
		return
	end

	-- Create answer input buffer
	state.answer_buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(state.answer_buf, "buftype", "nofile")
	api.nvim_buf_set_option(state.answer_buf, "modifiable", true)

	-- Set initial text
	local lines = vim.split(state.user_answer, "\n")
	if #lines == 0 or (#lines == 1 and lines[1] == "") then
		lines = { "" }
	end
	api.nvim_buf_set_lines(state.answer_buf, 0, -1, false, lines)

	-- Calculate window size and position (below main window)
	local main_win_config = api.nvim_win_get_config(state.win)
	local width = math.floor(main_win_config.width * 0.8)
	local height = 5
	local row = main_win_config.row + main_win_config.height - 15
	local col = main_win_config.col + math.floor((main_win_config.width - width) / 2)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Type Your Answer (ESC to save, Ctrl-C to cancel) ",
		title_pos = "center",
	}

	state.answer_win = api.nvim_open_win(state.answer_buf, true, opts)

	-- Set up autocommands to save on leave
	vim.cmd([[
    augroup AnkiAnswerInput
      autocmd!
      autocmd BufLeave <buffer> lua require('vimki').save_answer()
    augroup END
  ]])

	-- Add keymaps for the answer buffer
	local map_opts = { noremap = true, silent = true }
	api.nvim_buf_set_keymap(state.answer_buf, "n", "<Esc>", ':lua require("vimki").save_answer()<CR>', map_opts)
	api.nvim_buf_set_keymap(state.answer_buf, "i", "<C-c>", '<Esc>:lua require("vimki").cancel_answer()<CR>', map_opts)

	-- Start in insert mode
	vim.cmd("startinsert")
end

function M.save_answer()
	if not state.answer_buf or not api.nvim_buf_is_valid(state.answer_buf) then
		return
	end

	-- Get the answer text
	local lines = api.nvim_buf_get_lines(state.answer_buf, 0, -1, false)
	state.user_answer = table.concat(lines, "\n")

	-- Close answer window
	if state.answer_win and api.nvim_win_is_valid(state.answer_win) then
		api.nvim_win_close(state.answer_win, true)
	end
	state.answer_win = nil
	state.answer_buf = nil

	-- Clear autocommands
	vim.cmd("autocmd! AnkiAnswerInput")

	-- Update display
	render_card()

	-- Focus back on main window
	if state.win and api.nvim_win_is_valid(state.win) then
		api.nvim_set_current_win(state.win)
	end
end

function M.cancel_answer()
	-- Close answer window without saving
	if state.answer_win and api.nvim_win_is_valid(state.answer_win) then
		api.nvim_win_close(state.answer_win, true)
	end
	state.answer_win = nil
	state.answer_buf = nil

	-- Clear autocommands
	vim.cmd("autocmd! AnkiAnswerInput")

	-- Focus back on main window
	if state.win and api.nvim_win_is_valid(state.win) then
		api.nvim_set_current_win(state.win)
	end
end

function M.toggle_practice_mode()
	state.practice_mode = not state.practice_mode
	vim.notify(string.format("Practice mode: %s", state.practice_mode and "ON" or "OFF"), vim.log.levels.INFO)
	render_card()
end

function M.show_answer()
	if state.current_card and not state.show_answer then
		state.show_answer = true
		render_card()
	end
end

function M.rate_card(ease)
	if not state.current_card or not state.show_answer then
		return
	end

	-- Answer the card in Anki
	answer_card(state.current_card.cardId, ease)

	-- Update stats
	if ease == 1 then
		state.session_stats.incorrect = state.session_stats.incorrect + 1
	else
		state.session_stats.correct = state.session_stats.correct + 1
	end

	-- Next card
	state.card_index = state.card_index + 1
	load_next_card()
end

function M.skip_card()
	if not state.current_card then
		return
	end

	state.session_stats.skipped = state.session_stats.skipped + 1
	state.card_index = state.card_index + 1
	load_next_card()
end

function M.restart_session()
	M.close()
	M.start()
end

return M
