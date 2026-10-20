--[[--
AudioBookShelf API Client
Inspired by https://github.com/stradichenko/audiobook.koplugin/blob/master/absclient.lua
--]]
--

local _ = require("gettext")
local http = require("socket.http")
local logger = require("logger")
local ltn12 = require("ltn12")
local json = require("json")
local socket = require("socket")
local socketutil = require("socketutil")

local ABSClient = {}

function ABSClient:new(config)
	config = config or {}
	setmetatable(config, { __index = self })
	config.server_url = config.server_url or ""
	config.token = config.token or ""
	config.user_id = config.user_id or ""

	return config
end

function ABSClient:_request(endpoint, method, body)
	if not self.server_url or self.server_url == "" then
		return nil, _("No AudioBookShelf url configured")
	end

	local url = self.server_url .. endpoint
	local response = {}
	local headers = {
		["Content-Type"] = "application/json",
		["User-Agent"] = "ko-abs/1.0",
	}

	if self.token and self.token ~= "" then
		headers["Authorization"] = "Bearer " .. self.token
	end

	local request_body = nil
	if body then
		local ok, json_body = pcall(json.encode, body)
		if not ok then
			return nil, _("Failed to encode request body")
		end
		request_body = json_body
		headers["Content-Length"] = tostring(#request_body)
	end

	socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_BLOCK_TIMEOUT)

	local code, response_headers, status = socket.skip(
		1,
		http.request({
			url = url,
			method = method,
			headers = headers,
			source = request_body and ltn12.source.string(request_body) or nil,
			sink = ltn12.sink.table(response),
			redirect = false,
		})
	)

	socketutil:reset_timeout()

	if not code then
		return nil, _("Network error: no response from server")
	end

	-- If the request fails, code is a string error message
	if type(code) ~= "number" then
		return nil, _("Network error: ") .. tostring(code)
	end

	if code ~= 200 then
		return nil, _("Unexpected http response: ") .. tostring(code)
	end

	local response_body = table.concat(response)
	if not response_body or response_body == "" then
		return {}, nil
	end

	local ok, json_body = pcall(json.decode, response_body)
	if not ok then
		return { raw = response_body }, nil -- should we return an error?
	end
	return json_body, nil
end

function ABSClient:login(username, password)
	if not username or username == "" then
		return nil, nil, _("Username is required.")
	end

	if not password or password == "" then
		return nil, nil, _("Password is required.")
	end

	local data, err = self:_request("/login", "POST", {
		username = username,
		password = password,
	})

	if err or not data then
		return nil, nil, err
	end

	if data.error then
		return nil, nil, data.error
	end

	local token = data.token or data.user and data.user.token
	if not token then
		return nil, nil, _("Login succeeded but no token was returned.")
	end

	self.token = token
	self.user_id = data.user and data.user.id or ""

	return self.token, self.user_id, nil
end

function ABSClient:getLibraries()
	local data, err = self:_request("/api/libraries", "GET")

	if err or not data then
		return nil, err
	end

	if not data.libraries or type(data.libraries) ~= "table" then
		return nil, _("No libraries array in the response.")
	end

	return data.libraries, nil
end

function ABSClient:getLibraryItems(library_id, limit, page)
	limit = limit or 10
	page = page or 0
	local endpoint =
		string.format("/api/libraries/%s/items?limit=%d&page=%d&sort=media.metadata.title", library_id, limit, page)
	local data, err = self:_request(endpoint, "GET")

	if err or not data then
		return nil, err
	end

	return data, nil
end

-- careful what dest_path you call this with as it will mkdir
function ABSClient:downloadFile(id, dest_dir)
	if not id or id == "" then
		return _("No item id provided")
	end

	if not dest_dir or dest_dir == "" then
		return _("Invalid destination dir.")
	end

	local url = self.server_url .. "/api/items/" .. id .. "/download"

	local headers = {
		["User-Agent"] = "ko-abs/1.0",
	}
	if self.token and self.token ~= "" then
		headers["Authorization"] = "Bearer " .. self.token
	end

	-- careful what you call this with
	if dest_dir and dest_dir ~= "" then
		os.execute(string.format('mkdir -p "%s"', dest_dir))
	end

	local f, err = io.open(dest_dir .. "/" .. id, "wb")
	if err or not f then
		return _("Cannot open destination file.")
	end

	socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_BLOCK_TIMEOUT)

	local code, response_headers, status = socket.skip(
		1,
		http.request({
			url = url,
			method = "GET",
			headers = headers,
			sink = ltn12.sink.file(f),
			redirect = false,
		})
	)
	logger.info("ko-abs: HTTP response code:", tostring(code))
	logger.info("ko-abs: HTTP status:", tostring(status))

	socketutil:reset_timeout()

	if not code then
		return _("Network error: no response from server")
	end

	-- If the request fails, code is a string error message
	if type(code) ~= "number" then
		return _("Network error: ") .. tostring(code)
	end

	if code ~= 200 then
		return _("Unexpected http response: ") .. tostring(code)
	end

	return nil
end

return ABSClient
