local M = {
	max_conversation_history = 10,
	conversation_history = {},
	config = {},
}

local function loadEnv()
	local api_url = M.config.api_url
	local ai_api_key = M.config.api_key

	if api_url ~= nil and api_url ~= "" then
		return { api_url, ai_api_key }
	else
		error("Missing AI API URL and AI API KEY", 0)
	end
end

local function get_text_context()
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		vim.cmd('normal! "vy')
		return vim.fn.getreg("v")
	else
		return vim.fn.getline(".")
	end
end

local function chat_with_ai(prompt, callback)
	-- insert user prompts
	table.insert(M.conversation_history, {
		role = "user",
		content = prompt,
	})

	local messages = {}

	local start_index = math.max(1, #M.conversation_history - M.max_conversation_history + 1)

	for i = start_index, #M.conversation_history do
		table.insert(messages, M.conversation_history[i])
	end

	local data = vim.fn.json_encode({
		model = M.config.model,
		messages = messages,
		stream = false,
	})

	local curl_cmd = {
		"curl",
		"-s",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-H",
		"api-key: " .. M.config.api_key,
		"-d",
		data,
		M.config.api_url,
	}

	local output = {}
	print("Thinking...")
	vim.fn.jobstart(curl_cmd, {
		on_stdout = function(_, data_lines)
			for _, line in ipairs(data_lines) do
				if line ~= "" then
					table.insert(output, line)
				end
			end
		end,
		on_stderr = function(_, data_lines)
			local error_msg = table.concat(data_lines, "\n")
			if error_msg ~= "" then
				callback("Error: " .. error_msg, nil)
			end
		end,
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				local response = table.concat(output, "\n")
				if response ~= "" then
					local success, parsed = pcall(vim.fn.json_decode, response)
					if success and parsed.choices and parsed.choices[1] and parsed.choices[1].message then
						local content = parsed.choices[1].message.content
						callback(nil, content) -- success: error=nil, result=content
					else
						callback("Invalid response format: " .. response, nil)
					end
				else
					callback("Empty response", nil)
				end
			else
				callback("Command failed with exit code " .. exit_code, nil)
			end
		end,
	})
end

local function format_message_content(message)
	local formatted_lines = {}
	local lines = {}

	-- Split message into lines
	if message:find("\n") then
		for line in (message .. "\n"):gmatch("(.-)\n") do
			table.insert(lines, line)
		end
	else
		lines = { message }
	end

	local in_code_block = false
	local code_lang = ""

	for i, line in ipairs(lines) do
		-- Check for code block start/end
		local code_block_match = line:match("^```(.*)$")
		if code_block_match then
			if in_code_block then
				-- End of code block
				table.insert(formatted_lines, "└" .. string.rep("─", 60))
				in_code_block = false
				code_lang = ""
			else
				-- Start of code block
				code_lang = code_block_match ~= "" and code_block_match or "code"
				table.insert(formatted_lines, "┌─ " .. code_lang .. " " .. string.rep("─", 50))
				in_code_block = true
			end
		elseif in_code_block then
			-- Inside code block - add prefix
			table.insert(formatted_lines, "│ " .. line)
		else
			-- Regular text - handle markdown formatting
			local formatted_line = line

			-- Bold text **text** -> **text**
			formatted_line = formatted_line:gsub("%*%*(.-)%*%*", "**%1**")

			-- Italic text *text* -> *text*
			formatted_line = formatted_line:gsub("%*(.-)%*", "*%1*")

			-- Inline code `code` -> [code]
			formatted_line = formatted_line:gsub("`(.-)`", "[%1]")

			-- Headers
			if formatted_line:match("^#+%s") then
				formatted_line = "▶ " .. formatted_line:gsub("^#+%s", "")
			end

			-- Lists
			if formatted_line:match("^%s*[-*+]%s") then
				formatted_line = formatted_line:gsub("^(%s*)[-*+](%s)", "%1• %2")
			elseif formatted_line:match("^%s*%d+%.%s") then
				formatted_line = formatted_line:gsub("^(%s*)(%d+)%.(%s)", "%1%2.%3")
			end

			table.insert(formatted_lines, formatted_line)
		end
	end

	-- Close code block if still open
	if in_code_block then
		table.insert(formatted_lines, "└" .. string.rep("─", 60))
	end

	return formatted_lines
end

local function wrap_line(text, max_width)
	if #text <= max_width then
		return { text }
	end

	local lines = {}
	local current_line = ""

	for word in text:gmatch("%S+") do
		if #current_line + #word + 1 <= max_width then
			current_line = current_line == "" and word or current_line .. " " .. word
		else
			if current_line ~= "" then
				table.insert(lines, current_line)
			end
			current_line = word
		end
	end

	if current_line ~= "" then
		table.insert(lines, current_line)
	end

	return lines
end

local function add_messages(buf, win, sender, message)
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	local current_line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local timestamp = os.date("%H:%M")
	local win_width = vim.api.nvim_win_get_width(win)

	local formatted_lines = format_message_content(message)

	local sender_line
	if sender == "You" then
		sender_line = string.format("%s [%s]", sender, timestamp)
		local sender_pad = win_width - #sender_line - 2
		if sender_pad > 0 then
			sender_line = string.rep(" ", sender_pad) .. sender_line
		end
	else
		sender_line = string.format("[%s] %s", timestamp, sender)
	end

	table.insert(current_line, sender_line)

	for _, msg_line in ipairs(formatted_lines) do
		if sender == "You" then
			-- Right align user messages
			local wrapped_lines = wrap_line(msg_line, win_width - 4)
			for _, wrapped in ipairs(wrapped_lines) do
				local msg_pad = win_width - #wrapped - 2
				if msg_pad > 0 then
					table.insert(current_line, string.rep(" ", msg_pad) .. wrapped)
				else
					table.insert(current_line, wrapped)
				end
			end
		else
			-- Left align AI messages, but handle long lines
			local wrapped_lines = wrap_line(msg_line, win_width - 4)
			for _, wrapped in ipairs(wrapped_lines) do
				table.insert(current_line, wrapped)
			end
		end
	end

	-- Add empty line for spacing
	table.insert(current_line, "")

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, current_line)

	-- Scroll to bottom
	local line_count = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_win_set_cursor(win, { line_count, 0 })

	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

local function get_user_input(buf, win)
	vim.ui.input({
		prompt = "You: ",
	}, function(input)
		if input and input ~= "" then
			add_messages(buf, win, "You", input)

			chat_with_ai(input, function(error, ai_response)
				if error then
					add_messages(buf, win, M.config.model, "Error: " .. error)
				else
					add_messages(buf, win, M.config.model, ai_response)
				end
				vim.defer_fn(function()
					if vim.api.nvim_win_is_valid(win) then
						get_user_input(buf, win)
					end
				end, 100)
			end)
		end
	end)
end

local function clear_conversation_history()
	M.conversation_history = {}
	vim.notify("Conversation History Cleared")
end

local function open_floating_window()
	clear_conversation_history()
	local buf = vim.api.nvim_create_buf(false, true)
	local width = 80
	local height = 30
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = (vim.o.columns - width) / 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = "rounded",
		title = "Testing Floating Windows",
		title_pos = "center",
	})

	-- Make the content buf modifiable
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

	local success, env = pcall(loadEnv)

	if success then
		local api_url, ai_api_key = env[1], env[2]
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"Welcome to " .. M.config.model,
			"Press <Enter> to start chat or 'q' to quit the chat room",
		})
		vim.notify("Environment loading success...")
	else
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"Missing env:",
			env,
		})
		return
	end
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Close window
	local opts = { noremap = true, silent = true, buffer = buf }

	-- Close with q
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, opts)

	-- Start chat with Enter
	local user_input_fn = function()
		return get_user_input(buf, win)
	end
	vim.keymap.set("n", "<CR>", user_input_fn, opts)
	return { buf, win }
end

local function explain_code()
	local text = get_text_context()
	if text == "" then
		vim.notify("No code to explain")
		return
	end

	local filetype = vim.bo.filetype
	local prompt = string.format("Explain this %s code:\n\n%s", filetype, text)
	local success, win_float = pcall(open_floating_window)
	if not success and win_float ~= nil then
		vim.notify("Error open floating window: " .. win_float)
		return
	end
	local buf, win = win_float[1], win_float[2]
	chat_with_ai(prompt, function(error, ai_response)
		if error then
			add_messages(buf, win, M.config.model, "Error: " .. error)
		else
			add_messages(buf, win, M.config.model, ai_response)
		end
		vim.defer_fn(function()
			if vim.api.nvim_win_is_valid(win) then
				get_user_input(buf, win)
			end
		end, 100)
	end)
end

function setup(opts)
	opts = opts or {}

	for k, v in pairs(opts.config) do
		M.config[k] = v
	end

	table.insert(M.conversation_history, {
		role = "system",
		content = opts.system_role,
	})
	M.max_conversation_history = opts.max_conversation_history_len

	local keymap_opts = { noremap = true, silent = true }
	vim.keymap.set("n", "<leader>of", open_floating_window, keymap_opts)
	vim.keymap.set("n", "<leader>cf", clear_conversation_history, keymap_opts)
	vim.keymap.set(
		{ "n", "v" },
		"<leader>ssf",
		explain_code,
		vim.tbl_extend("force", keymap_opts, { desc = "Explain code" })
	)
end

return {
	setup = setup,
}
