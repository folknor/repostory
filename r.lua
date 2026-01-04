#!/usr/bin/lua
-- Please note the weird dependencies here;
-- https://github.com/folknor/luash
-- https://github.com/Lua-cURL/Lua-cURLv3
-- And yes, I know I could have used curl through luash. I wrote this script to get my feet wet with these libraries.

local _RELEASES = { "resolute", "questing", "plucky", "oracular" }
local _SPAM = {
	"https?://",
	"ppa.launchpad.net/",
	"ppa.launchpadcontent.net/",
	"/ubuntu",
	".com",
	"/deb",
	"/$",
}

local io = require("io")
local sh = require("sh")
local curl = require("lcurl")
local tput, grep, cat, ls = sh.command("tput"), sh.command("grep"), sh.command("cat"), sh.command("ls")
local _ = tostring

local colors = tonumber(_(tput("colors")))
local reset, red, green, white, bold = "", "", "", "", ""
if colors and colors > 7 then
	bold = _(tput("bold"))
	reset = _(tput("sgr0"))
	red = _(tput("setaf 1"))
	green = _(tput("setaf 2"))
	white = _(tput("setaf 7"))
end

-- Column widths will be calculated before printing
local colWidths = {}

-- Strip ANSI codes to get actual display width
local function stripAnsi(s)
	s = s:gsub("\027%([A-Z]", "")      -- character set selection (e.g. \027(B)
	s = s:gsub("\027%[[%d;]*[a-zA-Z]", "") -- CSI sequences (e.g. \027[32m, \027[m)
	return s
end

local function padRight(s, width)
	local visibleLen = #stripAnsi(s)
	return s .. string.rep(" ", math.max(0, width - visibleLen))
end

local outputRows = {}
local function queueRow(tbl, prefix)
	outputRows[#outputRows + 1] = { cells = tbl, prefix = prefix or "" }
	for i, cell in ipairs(tbl) do
		local w = #stripAnsi(cell)
		colWidths[i] = math.max(colWidths[i] or 0, w)
	end
end

local function flushOutput()
	for _, row in ipairs(outputRows) do
		io.write(row.prefix)
		for i, cell in ipairs(row.cells) do
			if i < #row.cells then
				io.write(padRight(cell, colWidths[i] + 2))
			else
				io.write(cell)
			end
		end
		io.write(reset, "\n")
	end
end

local debGrep = "deb\\ "
local dotD = "/etc/apt/sources.list.d/"
local sourceLs = _(grep(ls(dotD), "-v", ".save"))
local sources = { _(grep(cat("/etc/apt/sources.list"), debGrep)) }
for file in sourceLs:gmatch("[^\n]+") do
	if file:match("%.list$") then
		sources[#sources + 1] = _(grep(cat(dotD .. file), debGrep))
	end
end
for i = #sources, 1, -1 do if sources[i] == "" then table.remove(sources, i) end end -- '/^$/d'

-- Parse DEB822 .sources files
local deb822sources = {}
for file in sourceLs:gmatch("[^\n]+") do
	if file:match("%.sources$") then
		local content = _(cat(dotD .. file))
		local uri, suite
		for line in content:gmatch("[^\n]+") do
			local key, value = line:match("^(%S+):%s*(.+)$")
			if key == "URIs" then uri = value end
			if key == "Suites" then suite = value end
		end
		if uri and suite then
			deb822sources[#deb822sources + 1] = { uri = uri, suite = suite }
		end
	end
end

local stdAffixes = { "(%a+)%-proposed", "(%a+)%-updates", "(%a+)%-backports", "(%a+)%-security" }

local mirrorData = {}
local function getMirrorData(url)
	if mirrorData[url] then return mirrorData[url] end
	local data = ""
	local get = curl.easy({
		url = url,
		writefunction = function(incoming)
			data = data .. incoming
			return true
		end,
	})
	get:perform()
	get:close()
	mirrorData[url] = select(3, data:find("^(%S+)\n"))
	return mirrorData[url]
end

local unique = {}
for i = 1, #sources do
	local s = sources[i]
	for line in s:gmatch("[^\n]+") do
		if not line:find("help%.ubuntu%.com") then
			-- Remove trailing comments, deb prefix, and [arch=x,y]
			local res = line:gsub("%s?#.*", ""):gsub("deb%s+", ""):gsub("%[.*%]%s+", "")
			local url, repo = res:match("^(%S+)%s+([%S]+)")
			if url and repo then
				if url:find("mirrors.txt$") then
					url = getMirrorData(url:gsub("mirror://", "http://"))
				end
				if not url:find("/$") then url = url .. "/" end
				local strippedRepo = repo
				for k = 1, 4 do
					local stripped = repo:match(stdAffixes[k])
					if stripped then
						strippedRepo = stripped; break
					end
				end
				unique[url] = strippedRepo
			end
		end
	end
end

-- Add DEB822 sources to unique
for _, src in ipairs(deb822sources) do
	local url = src.uri
	local repo = src.suite
	if not url:find("/$") then url = url .. "/" end
	local strippedRepo = repo
	for k = 1, 4 do
		local stripped = repo:match(stdAffixes[k])
		if stripped then
			strippedRepo = stripped; break
		end
	end
	unique[url] = strippedRepo
end

local data = {}
local repoFormat = "%sdists/"
for url, repo in pairs(unique) do
	data[url] = { html = "", repo = repo }
	local get = curl.easy({
		url = repoFormat:format(url),
		writefunction = function(incoming)
			data[url].html = data[url].html .. incoming
			return true
		end,
	})
	get:perform()
	get:close()
end

for url, meta in pairs(data) do
	local unfucked = url
	for _, remove in next, _SPAM do unfucked = unfucked:gsub(remove, "") end
	meta.unfucked = unfucked
	meta.dists = {}
	for href in meta.html:gmatch("href=\"(%S+)\"") do
		meta.dists[(href:gsub("/", "")):lower()] = true
	end
end

local greenYes = green .. "[Yes]" .. reset
local bracketYes = white .. "[Yes]" .. reset
local redYes = red .. "Yes" .. reset
local plain = "Yes"

local sortedUnfucked = {}
for url in pairs(data) do
	sortedUnfucked[#sortedUnfucked + 1] = url
end
table.sort(sortedUnfucked, function(a, b) return data[b].unfucked > data[a].unfucked end)

local printDists = {}
for _, dist in next, _RELEASES do
	printDists[#printDists + 1] = dist:upper()
end
printDists[#printDists + 1] = "URL"
queueRow(printDists, bold .. white)

for _, url in next, sortedUnfucked do
	local meta = data[url]
	local currentDistribution = meta.repo
	local available = meta.dists

	local printThis = {}
	local foundCurrent = false
	local hadNo = false

	for i, check in next, _RELEASES do
		if available[check] then
			if currentDistribution == check then
				foundCurrent = true
				if i == 1 or hadNo then
					printThis[i] = greenYes
				else
					printThis[i] = bracketYes
				end
			else
				if not foundCurrent then
					printThis[i] = redYes
				else
					printThis[i] = plain
				end
			end
		else
			hadNo = true
			printThis[i] = "-"
		end
	end
	if foundCurrent then
		printThis[#printThis + 1] = meta.unfucked
	else
		printThis[#printThis + 1] = meta.unfucked .. " (" .. currentDistribution .. ")"
	end
	queueRow(printThis)
end

flushOutput()
