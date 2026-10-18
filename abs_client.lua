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
local skip = require("socket.skip")
local socketutil = require("socketutil")

local ABSClient = {}

function ABSClient:new(config)
	config = config or {}
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

	local code, response_headers, status = skip(
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
