local fs = require "luci.fs"
local http = luci.http
local nfs = require "nixio.fs"
local nixio = require "nixio"
local format = string.format

local ful = SimpleForm("upload", translate("Upload"), nil)
ful.reset = false
ful.submit = false

local sul = ful:section(SimpleSection, "", translate("Upload file to '/tmp/upload/'"))
local fu = sul:option(FileUpload, "")
fu.template = "cbi/exother_upload"
local um = sul:option(DummyValue, "", nil)
um.template = "cbi/exother_dvalue"

local fdl = SimpleForm("download", translate("Download"), nil)
fdl.reset = false
fdl.submit = false
local sdl = fdl:section(SimpleSection, "", translate("Download file or foler"))
local fd = sdl:option(FileUpload, "")
fd.template = "cbi/exother_download"
local dm = sdl:option(DummyValue, "", nil)
dm.template = "cbi/exother_dvalue"

local ul_path = "/tmp/upload/"
local dl_path
local inits = {}
local inits2 = {}
local byteUnits = {" kB", " MB", " GB", " TB"}

local function GetSizeStr(size)
	if size < 1024 then
		return format("%d B", size)
	end
	local i = 0
	repeat
		size = size / 1024
		i = i + 1
	until size < 1024 or i == #byteUnits
	return format("%.1f%s", size, byteUnits[i])
end

local function SetTableEntries(table, path)
	if not path then
		return
	end
	path = path .. "*"
	local attr
	for i, f in ipairs(fs.glob(path)) do
		attr = nfs.stat(f)
		if attr then
			table[i] = {}
			table[i].name = nfs.basename(f)
			table[i].mtime = os.date("%Y-%m-%d %H:%M:%S", attr.mtime)
			table[i].modestr = attr.modestr
			table[i].size = GetSizeStr(attr.size)
			table[i].remove = attr.type == "reg"
			table[i].install = false
		end
	end
end

local function IsIpkFile(name)
	name = name or ""
	local ext = string.lower(string.sub(name, -4, -1))
	return ext == ".ipk"
end

local function Download(sPath)
	local sFile, fd, block
	sPath = sPath or http.formvalue("dlfile")
	sFile = nfs.basename(sPath)
	if fs.isdirectory(sPath) then
		fd = io.popen('tar -C "%s" -cz .' % {sPath}, "r")
		sFile = sFile .. ".tar.gz"
	else
		fd = nixio.open(sPath, "r")
	end
	if not fd then
		dm.value = translate("Couldn't open file: ") .. sPath
		return
	end
	dm.value = nil
	http.header("Content-Disposition", 'attachment; filename="%s"' % {sFile})
	http.prepare_content("application/octet-stream")
	while true do
		block = fd:read(nixio.const.buffersize)
		if (not block) or (#block == 0) then
			break
		else
			http.write(block)
		end
	end
	fd:close()
	http.close()
end

local function List(dl_form)
	dl_path = http.formvalue("dlfile")
	if fs.isdirectory(dl_path) then
		if string.sub(dl_path, -1) ~= "/" then
			dl_path = dl_path .. "/"
		end
		dl_form.description = format('<span style="color: black">%s</span>', dl_path)
	else
		dl_form.description = format('<span style="color: red">%s</span>', translate("Not a folder!"))
	end
end

local dir, fd
dir = ul_path
nfs.mkdir(dir)
http.setfilehandler(
	function(meta, chunk, eof)
		if not fd then
			if not meta then
				return
			end

			if meta and chunk then
				fd = nixio.open(dir .. meta.file, "w")
			end

			if not fd then
				um.value = translate("Create upload file error.")
				return
			end
		end
		if chunk and fd then
			fd:write(chunk)
		end
		if eof and fd then
			fd:close()
			fd = nil
			um.value = translate("File saved to") .. ' "/tmp/upload/' .. meta.file .. '"'
		end
	end
)

--Upload Form
local ul_form = SimpleForm("filelist", translate("Upload file list"), nil)
ul_form.reset = false
ul_form.submit = false

-- Download form
local dl_form = SimpleForm("dlfilelist", translate("Download file list"), nil)
dl_form.reset = false
dl_form.submit = false

if luci.http.formvalue("upload") then
	local f = luci.http.formvalue("ulfile")
	if #f <= 0 then
		um.value = translate("No specified upload file.")
	end
elseif luci.http.formvalue("download") then
	Download()
elseif luci.http.formvalue("list") then
	List(dl_form)
end

SetTableEntries(inits, ul_path)
SetTableEntries(inits2, dl_path)

local tb = ul_form:section(Table, inits)
local nm = tb:option(DummyValue, "name", translate("File name"))

local mt = tb:option(DummyValue, "mtime", translate("Last Modified"))
local ms = tb:option(DummyValue, "modestr", translate("Permissions"))
local sz = tb:option(DummyValue, "size", translate("Size"))
local btnrm = tb:option(Button, "remove", translate("Remove"))
btnrm.render = function(self, section, scope)
	if inits[section].remove then
		self.inputstyle = "remove"
		Button.render(self, section, scope)
	end
end

btnrm.write = function(self, section)
	local v = nfs.unlink(ul_path .. nfs.basename(inits[section].name))
	if v then
		table.remove(inits, section)
	end
	return v
end

local btnins = tb:option(Button, "install", translate("Install"))
btnins.render = function(self, section, scope)
	if not inits[section] then
		return false
	end
	if IsIpkFile(inits[section].name) then
		self.inputstyle = "apply"
		Button.render(self, section, scope)
	end
end
btnins.write = function(self, section)
	local r = luci.sys.exec(format('opkg --force-reinstall install "/tmp/upload/%s"', inits[section].name))
	ul_form.description = format('<span style="color: red">%s</span>', r)
end

local tb2 = dl_form:section(Table, inits2)
local nm2 = tb2:option(DummyValue, "name", translate("File name"))
local mt2 = tb2:option(DummyValue, "mtime", translate("Last Modified"))
local ms2 = tb2:option(DummyValue, "modestr", translate("Permissions"))
local sz2 = tb2:option(DummyValue, "size", translate("Size"))
local btnrm2 = tb2:option(Button, "remove", translate("Remove"))
btnrm2.render = function(self, section, scope)
	if not inits2[section].remove then
		self.inputstyle = "remove"
		Button.render(self, section, scope)
	end
end
btnrm2.write = function(self, section)
	local v = nfs.unlink(dl_path .. nfs.basename(inits2[section].name))
	if v then
		table.remove(inits2, section)
	end
	return v
end

return ful, fdl, dl_form, ul_form
