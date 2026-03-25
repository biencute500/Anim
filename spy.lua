-- SimpleSpy (rút gọn) + Server->Client logger
-- Lưu ý: yêu cầu môi trường exploit hỗ trợ hookfunction / getrawmetatable / setreadonly / hookmetamethod

-- ================== Khởi tạo nhanh GUI & state ==================
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SimpleSpy2 = Instance.new("ScreenGui")
SimpleSpy2.Name = "SimpleSpy2"
SimpleSpy2.ResetOnSpawn = false
SimpleSpy2.Parent = CoreGui
SimpleSpy2.Enabled = true

-- (UI tối giản: chỉ dùng Output và không cần panel, để tập trung chức năng)
local logs = {}
local connections = {}
local toggle = false

-- ================== Serializer gốc (giữ nguyên lõi) ==================
local topstr, bottomstr, getnilrequired
local indent = 4
local function safetostring(v)
	if typeof(v) == "userdata" or type(v) == "table" then
		local mt = getrawmetatable(v)
		local badtostring = mt and rawget(mt, "__tostring")
		if mt and badtostring then
			rawset(mt, "__tostring", nil)
			local out = tostring(v)
			rawset(mt, "__tostring", badtostring)
			return out
		end
	end
	return tostring(v)
end
local function formatstr(s, indentation)
	indentation = indentation or 0
	local buildStr, i, char = {}, 1, s:sub(1,1)
	local indentStr
	while char ~= "" do
		if char == '"' then buildStr[i] = '\\"'
		elseif char == "\\" then buildStr[i] = "\\\\"
		elseif char == "\n" then buildStr[i] = "\\n"
		elseif char == "\t" then buildStr[i] = "\\t"
		elseif string.byte(char) > 126 or string.byte(char) < 32 then
			buildStr[i] = string.format("\\%d", string.byte(char))
		else buildStr[i] = char end
		i += 1; char = s:sub(i,i)
		if i % 200 == 0 then
			indentStr = indentStr or string.rep(" ", indentation + indent)
			table.move({ '"\n', indentStr, '... "' }, 1, 3, i, buildStr)
			i += 3
		end
	end
	return table.concat(buildStr)
end
local function handlespecials(v, indentation) return formatstr(v, indentation) end
local function v2s(v, l, p, n, vtv, i, pt, path, tables, tI)
	if not tI then tI = {0} else tI[1]+=1 end
	if typeof(v) == "number" then
		if v == math.huge then return "math.huge"
		elseif tostring(v):match("nan") then return "0/0 --[[NaN]]" end
		return tostring(v)
	elseif typeof(v) == "boolean" then return tostring(v)
	elseif typeof(v) == "string" then return '"'..handlespecials(v,l)..'"'
	elseif typeof(v) == "function" then return "function()end --[["..tostring(v).."]]"
	elseif typeof(v) == "table" then
		local s, size = "{", 0
		l = (l or 0) + indent
		tables = tables or {}
		for _, t in pairs(tables) do if rawequal(t, v) then return "{} --[[DUPLICATE]]" end end
		table.insert(tables, v)
		for k,val in pairs(v) do
			size+=1
			if size>(_G.SimpleSpyMaxTableSize or 1000) then
				s = s.."\n"..string.rep(" ", l).."-- MAX TABLE SIZE"
				break
			end
			s = s.."\n"..string.rep(" ", l).."["..v2s(k,l,p,n,vtv,i,pt,path,tables,tI).."] = "..v2s(val,l,p,n,vtv,k,v,path,tables,tI)..","
		end
		if #s>1 then s = s:sub(1,#s-1) end
		if size>0 then s = s.."\n"..string.rep(" ", l - indent) end
		return s.."}"
	elseif typeof(v) == "Instance" then
		return 'game.'..v:GetFullName()
	elseif typeof(v) == "userdata" then return "newproxy(true)"
	elseif type(v) == "userdata" then return "newproxy(true)"
	else return "nil --[["..typeof(v).."]]" end
end
local SimpleSpy = {}
function SimpleSpy:ValueToString(value) return v2s(value) end
function SimpleSpy:ValueToVar(value, variablename)
	variablename = variablename or 1
	return "local "..tostring(variablename).." = "..v2s(value).."\n"
end

-- ================== Logger server->client ==================
local function newRemote(kind, name, args, remote)
	table.insert(logs, {kind=kind,name=name,args=args,remote=remote})
	-- hiển thị ra Output
	print(("[%s] %s"):format(kind:upper(), name))
	for i,val in ipairs(args) do
		print(("Arg[%d]:\n%s"):format(i, SimpleSpy:ValueToString(val)))
	end
	print("------")
end

local function logServerToClient(remote, kind, args)
	newRemote(kind, remote.Name.." [S->C]", args, remote)
end

local function attachServerListeners(obj)
	if obj:IsA("RemoteEvent") then
		local conn = obj.OnClientEvent:Connect(function(...)
			logServerToClient(obj, "event", { ... })
		end)
		table.insert(connections, conn)
	elseif obj:IsA("RemoteFunction") then
		local prev = obj.OnClientInvoke
		obj.OnClientInvoke = function(...)
			logServerToClient(obj, "function", { ... })
			if prev then return prev(...) end
			return nil -- tránh lỗi nếu server chờ return
		end
	end
end

-- ================== Main ==================
pcall(function()
	for _, inst in ipairs(game:GetDescendants()) do
		attachServerListeners(inst)
	end
	table.insert(connections, game.DescendantAdded:Connect(attachServerListeners))
	toggle = true
	print("[SimpleSpy] GUI ready & server->client logger active.")
end)

-- cleanup on shutdown (tuỳ môi trường)
_G.SimpleSpyShutdown = function()
	for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	SimpleSpy2:Destroy()
end
_G.SimpleSpyExecuted = true
getgenv().SimpleSpy = SimpleSpy
