local fs = require "luci.fs"
local http = luci.http
local nfs = require "nixio.fs"

ful = SimpleForm("upload", translate("Upload"), nil)
ful.reset = false
ful.submit = false

sul = ful:section(SimpleSection, "", translate("Upload file to '/tmp/upload/'"))
fu = sul:option(FileUpload, "")
fu.template = "cbi/exother_upload"
um = sul:option(DummyValue, "", nil)
um.template = "cbi/exother_dvalue"

fdl = SimpleForm("download", translate("Download"), nil)
fdl.reset = false
fdl.submit = false
sdl = fdl:section(SimpleSection, "", translate("Download file"))
fd = sdl:option(FileUpload, "")
fd.template = "cbi/exother_download"
dm = sdl:option(DummyValue, "", nil)
dm.template = "cbi/exother_dvalue"

function Download()
    local sPath, sFile, fd, block
    sPath = http.formvalue("dlfile")
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

local byteUnits = {" kB", " MB", " GB", " TB"}
local function GetSizeStr(size)
    local i = 0
    repeat
        size = size / 1000
        i = i + 1
    until (size <= 1000)
    return string.format("%.1f", size) .. byteUnits[i]
end

local init, inits2, attr = {}
local function SetTableEntries(table, path)
    local attr
    for i, f in ipairs(nfs.glob(path)) do
        attr = nfs.stat(f)
        if attr then
            table[i] = {}
            table[i].name = nfs.basename(f)
            table[i].mtime = os.date("%Y-%m-%d %H:%M:%S", attr.mtime)
            table[i].modestr = attr.modestr
            table[i].size = GetSizeStr(attr.size)
            table[i].remove = 0
            table[i].install = false
        end
    end
end

local ul_path = "/tmp/upload/"
local dl_path
function List()
    dl_path = http.formvalue("dlfile")
    if fs.isdirectory(dl_path) then
        if string.sub(dl_path, -1) ~= "/" then
            dl_path = dl_path .. "/"
        end
        SetTableEntries(inits2, dl_path .. "*")
        for i, f in ipairs(nfs.glob()) do
            attr = nfs.stat(f)
            if attr then
                inits2[i] = {}
                inits2[i].name = nfs.basename(f)
                inits2[i].mtime = os.date("%Y-%m-%d %H:%M:%S", attr.mtime)
                inits2[i].modestr = attr.modestr
                inits2[i].size = GetSizeStr(attr.size)
                inits2[i].remove = 0
            end
        end
    else
        form2.description = string.format('<span style="color: red">%s</span>', tranlate("Not a folder"))
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

if luci.http.formvalue("upload") then
    local f = luci.http.formvalue("ulfile")
    if #f <= 0 then
        um.value = translate("No specify upload file.")
    end
elseif luci.http.formvalue("download") then
    Download()
elseif luci.http.formvalue("list") then
    List()
end

local inits = {}
SetTableEntries(inits, "/tmp/upload/*")

form = SimpleForm("filelist", translate("Upload file list"), nil)
form.reset = false
form.submit = false

tb = form:section(Table, inits)
nm = tb:option(DummyValue, "name", translate("File name"))
mt = tb:option(DummyValue, "mtime", translate("Modify time"))
ms = tb:option(DummyValue, "modestr", translate("Permissions"))
sz = tb:option(DummyValue, "size", translate("Size"))
btnrm = tb:option(Button, "remove", translate("Remove"))
btnrm.render = function(self, section, scope)
    self.inputstyle = "remove"
    Button.render(self, section, scope)
end

btnrm.write = function(self, section)
    local v = nfs.unlink(ul_path .. nfs.basename(inits[section].name))
    if v then
        table.remove(inits, section)
    end
    return v
end

function IsIpkFile(name)
    name = name or ""
    local ext = string.lower(string.sub(name, -4, -1))
    return ext == ".ipk"
end

btnis = tb:option(Button, "install", translate("Install"))
btnis.template = "cbi/exother_button"
btnis.render = function(self, section, scope)
    if not inits[section] then
        return false
    end
    if IsIpkFile(inits[section].name) then
        scope.display = ""
    else
        scope.display = "none"
    end
    self.inputstyle = "apply"
    Button.render(self, section, scope)
end

btnis.write = function(self, section)
    local r = luci.sys.exec(string.format('opkg --force-depends --force-reinstall install "/tmp/upload/%s"', inits[section].name))
    form.description = string.format('<span style="color: red">%s</span>', r)
end

form2 = SimpleForm("dlfilelist", translate("Download file list"), nil)
form2.reset = false
form2.submit = false
form2.description = dl_path

local inits2 = {}
tb2 = form2:section(Table, inits2)
nm2 = tb2:option(DummyValue, "name", translate("File name"))
mt2 = tb2:option(DummyValue, "mtime", translate("Last Modified"))
ms2 = tb2:option(DummyValue, "modestr", translate("Permissions"))
sz2 = tb2:option(DummyValue, "size", translate("Size"))
btnrm2 = tb2:option(Button, "remove", translate("Remove"))
btnrm2.render = function(self, section, scope)
    self.inputstyle = "remove"
    Button.render(self, section, scope)
end

btnrm2.write = function(self, section)
    local v = nfs.unlink(dl_path .. nfs.basename(inits2[section].name))
    if v then
        table.remove(inits2, section)
    end
    return v
end

return ful, fdl, form2, form
