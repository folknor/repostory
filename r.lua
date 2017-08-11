#!/usr/bin/lua
local _RELEASES = {"artful", "zesty", "yakkety", "xenial"}
local _SPAM = {
	"https?://",
	"ppa.launchpad.net/",
	"/ubuntu",
	".com",
	"/deb",
	"/$",
}

local io = require("io")
local sh = require("sh")
local curl = require("lcurl")
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

local function print(tbl, ...) if select("#", ...) > 0 then io.write(..., table.concat(tbl, "\t"), reset, "\n") else io.write(table.concat(tbl, "\t"), reset, "\n") end end

local debGrep = "deb\\ "
local dotD = "/etc/apt/sources.list.d/"
local sourceLs = _(grep(ls(dotD), "-v", ".save"))
local sources = {_(grep(cat("/etc/apt/sources.list"), debGrep))}
for file in sourceLs:gmatch("[^\n]+") do sources[#sources+1] = _(grep(cat(dotD .. file), debGrep)) end
for i = #sources, 1, -1 do if sources[i] == "" then table.remove(sources, i) end end -- '/^$/d'
local stdAffixes = { "(%a+)%-proposed", "(%a+)%-updates", "(%a+)%-backports", "(%a+)%-security" }

local unique = {}
for i = 1, #sources do
	local s = sources[i]
	for line in s:gmatch("[^\n]+") do
		if not line:find("help%.ubuntu%.com") then
			-- Remove trailing comments, deb prefix, and [arch=x,y]
			local res = line:gsub("%s?#.*", ""):gsub("deb%s+", ""):gsub("%[.*%]%s+", "")
			local url, repo = res:match("^(%S+)%s+([%S]+)")
			if not url:find("/$") then url = url .. "/" end
			local strippedRepo = repo
			for k = 1, 4 do
				local stripped = repo:match(stdAffixes[k])
				if stripped then strippedRepo = stripped; break end
			end
			unique[url] = strippedRepo
		end
	end
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
local redYes =  red .. "Yes" .. reset
local plain = "Yes"

local sortedUnfucked = {}
for url in pairs(data) do
	sortedUnfucked[#sortedUnfucked+1] = url
end
table.sort(sortedUnfucked, function(a, b) return data[b].unfucked > data[a].unfucked end)

local printDists = {}
for _, dist in next, _RELEASES do
	printDists[#printDists+1] = dist:upper()
end
printDists[#printDists+1] = "URL"
print(printDists, bold, white)

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
		printThis[#printThis + 1] = meta.unfucked
		printThis[#printThis + 1] = "(" .. currentDistribution .. ")"
	end
	print(printThis)
end
