local dev, com, str, _x, empty, tru, space, ourname, tab, leshort = component, computer, string, "%.2x", "", true, " ", "Super Multi Boot", table, "<H"
local cproxy, clist, cinvoke, lassert, lload, lsetmetatable, spack, sunpack, sfind, sbyte, srep, sformat, sgsub, ssub, lerror, spacksize =
      dev.proxy, dev.list, dev.invoke, assert, load, setmetatable, str.pack, str.unpack, str.find, str.byte, str.rep,
      str.format, str.gsub, str.sub, error, str.packsize
_BOOT=ourname
_BIOS=ourname -- both like classic zorya and zorya neo
-- our basic info
_SMB = {
	version = "0.1-alpha",
	git = "$[[git rev-parse --short HEAD]]"
}

@[[if svar.get("BUILD") ~= "release" then]]
local function debug_print(...)
	local t = tab.pack(...)
	for i=1, #t do
		t[i] = tostring(t[i])
	end
	cinvoke(clist("ocemu")(), "log", tab.concat(t, "\t"))
end
@[[else]]
local function debug_print()end
@[[end]]
local function a2b(addr)
	addr = sgsub(addr, "%-", empty)
	local baddr = empty
	for i=1, #addr, 2 do
		baddr = baddr .. str.char(tonumber(ssub(addr, i, i+1), 16))
	end
	return baddr
end

local function b2a(addr)
	addr = ssub(addr, 1, 16)
	return sformat(sformat("%s-%s%s", srep(_x, 4), srep(_x.._x.."-", 3),srep(_x, 6)), sbyte(addr, 1, #addr))
end

local function readfile(fs, hand)
	local buffer = empty
	local data, reason
	repeat
		data = fs.read(hand, math.huge)
		if not data and reason then
			lerror(reason)
		end
		buffer = buffer .. (data or empty)
	until not data or data == ""
	return buffer
end

local function getdata(req)
	local data = empty
	while tru do
		local chunk, reason = req.read()
		if not chunk then req.close() if reason then lerror(reason, 0) end break end
		data = data .. chunk
	end
	return data
end

local function establish_connection(dev, ...)
	for i=1, 3 do
		local req, err = dev.request(...)
		if dev then return req end
	end
	lerror("couldn't connect", 0)
end

local handlers = {}

local function addboot(id, boot, read)
	handlers[id] = {boot, read}
end

local config = {}

local function addconfig(key, handler)
	config[key] = handler
end

local function cfgset(key, value)
	config[key](value)
end

local btable = {}

local function load_data(cdat)
	local pos = 1
	while sbyte(cdat, pos) do
		local handler, namesize, size = sbyte(cdat, pos, pos+2)
		debug_print(sformat("handler %i -> namesize: %i; argsize: %i", handler, namesize, size))
		local name, bdat = ssub(cdat, pos+3, pos+2+namesize), tab.pack(assert(handlers[handler], "handler "..handler.." not found")[2](ssub(cdat, pos+3+namesize, pos+2+namesize+size)))
		if (bdat.n > 0) then
			btable[#btable+1] = {name,handler,bdat}
		end
		pos = pos+size+namesize+3
	end
end

local sel, timeout, skip, scode, skey = 1, 0, false, 0, 0

addconfig(0x0001, function(v)
	sel = #btable+sbyte(v)
end)

addconfig(0x0002, function(v)
	sel = sunpack(leshort, v)
end)

addconfig(0x0003, function(v)
	timeout = sunpack("f", v)
end)

addconfig(0x0004, function(v)
	skip = sbyte(v) > 0
end)

addconfig(0x0005, function(v)
	skey, scode = sunpack("<HH", v)
end)

-- insert handlers here

--#include "src/extended.lua"
--#include "src/bios.lua"
--#include "src/file.lua"
--#include "src/text.lua"
--#include "src/config.lua"
--#include "src/osdi.lua"
--#include "src/net.lua"

-- all handlers inserted
debug_print("loading configuration data...")
local eedat = cinvoke(clist("eeprom")(), "getData")
debug_print("loaded configuration data: "..#eedat.." bytes")
load_data(eedat)

-- display menu
debug_print("gpu init")
local gpu = cproxy(clist("gpu")())
local screen = clist("scre")()
debug_print("binding screen "..screen.." to gpu "..gpu.address)
gpu.bind(screen)
local white, black, w, h = 0xFFFFFF, 0, gpu.getResolution()
debug_print("setup colors")
gpu.setBackground(black)
gpu.setForeground(white)
debug_print("clear")
gpu.fill(1, 1, w, h, space)
local function cls()gpu.fill(1,1,w,h,space)end
local upper_left, horizontal, upper_right, vertical, lower_left, lower_right = "┌", "─", "┐", "│", "└", "┘"
local maxsize = (w-#ourname)
gpu.set(maxsize//2, 1, ourname)
gpu.set(1, 2, upper_left)
gpu.set(2, 2, srep(horizontal, w-2))
gpu.set(w, 2, upper_right)
for i=1, h-6 do
	gpu.set(1, i+2, vertical)
	gpu.set(w, i+2, vertical)
end
gpu.set(1, h-3, lower_left)
gpu.set(2, h-3, srep(horizontal, w-2))
gpu.set(w, h-3, lower_right)
gpu.set(1, h-1, "Use ↑ and ↓ keys to select which entry is highlighted.")
gpu.set(1, h, "Use ENTER to boot the selected entry.")
local ypos = 1
local cancelled = false
local function boot()
	gpu.setBackground(black)
	gpu.setForeground(white)
	debug_print(tab.unpack(btable[sel][3]))
	handlers[btable[sel][2]][1](tab.unpack(btable[sel][3]))
end
local function redraw()
	for i=1, h-6 do
		local ent = btable[ypos+i-1]
		if not ent then break end
		local name = ent[1]
		if not name then break end
		local short = name:sub(1, w-2)
		if short ~= name then
			short = short:sub(1, #sub-3).."..."
		end
		if (#short < w-2) then
			short = short .. srep(space, w-2-#short)
		end
		if (sel == ypos+i-1) then
			gpu.setBackground(white)
			gpu.setForeground(black)
		else
			gpu.setBackground(black)
			gpu.setForeground(white)
		end
		gpu.set(2, i+2, short)
	end
end
local stime = computer.uptime()
if (skip and (scode ~= 0 or skey ~= 0)) then
	local sig, key, code
	repeat
		sig, _, key, code = computer.pullSignal(0)
		if (sig == "key_down" and key == skey and code == scode) then
			skip = false
		end
	until not sig
	if skip then
		boot()
	end
end
if timeout == 0 then
	cancelled = true
end
while true do
	redraw()
	local sig, _, key, code = computer.pullSignal(0.1)
	gpu.setBackground(black)
	gpu.setForeground(white)
	if (timeout > 0 and not cancelled) then
		gpu.set(1, h-2, "Automatically booting in "..math.floor(timeout-(computer.uptime()-stime)).."s.")
	else
		gpu.set(1, h-2, srep(space, w))
	end
	if ((computer.uptime()-stime) >= timeout and not cancelled) then
		boot()
	end
	if (sig == "key_down") then
		cancelled = true
		if (key == 0 and code == 200) then
			sel = sel - 1
			if (sel < 1) then
				sel = 1
			elseif (sel < ypos) then
				ypos = ypos - 1
			end
		elseif (key == 0 and code == 208) then
			sel = sel + 1
			if (sel > #btable) then
				sel = #btable
			elseif (sel > ypos+h+7) then
				ypos = ypos+1
			end
		elseif (key == 13 and code == 28) then
			boot()
		end
	end
end