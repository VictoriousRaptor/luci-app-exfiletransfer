--[[
luci-app-filetransfer
Description: File upload / download
Author: yuleniwo  xzm2@qq.com  QQ:529698939
Modify: ayongwifi@126.com  www.openwrtdl.com
]]--

module("luci.controller.exfiletransfer", package.seeall)

function index()
	entry({"admin", "system", "exfiletransfer"}, form("updownload"), _("EXFileTransfer"),89)
end
