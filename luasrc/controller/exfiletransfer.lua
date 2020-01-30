--[[
luci-app-exfiletransfer
Description: File upload / download
Original Author: yuleniwo  xzm2@qq.com  QQ:529698939
Modify: ayongwifi@126.com  www.openwrtdl.com
Modify: VictoriousRaptor@github
]]--

module("luci.controller.exfiletransfer", package.seeall)

function index()
	entry({"admin", "system", "exfiletransfer"}, upload_form("exupdownload"), _("EXFileTransfer"), 89)
end
