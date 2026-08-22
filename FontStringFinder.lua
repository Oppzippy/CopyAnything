local addon = select(2, ...).addon
local L = addon.L

local MouseIsOver, EnumerateFrames = MouseIsOver, EnumerateFrames

---@return boolean
local function canAccessValueCompat(value)
	return WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE or canaccessvalue(value)
end

---@return boolean
local function canAccessAllValuesCompat(...)
	return WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE or canaccessallvalues(...)
end

---@param value Frame
---@return boolean
local function isAnchoringSecretCompat(value)
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and value:IsAnchoringSecret()
end

---@param value Frame
---@return boolean
local function hasAnySecretAspectCompat(value)
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and value:HasAnySecretAspect()
end

-- 新增：安全的 IsVisible / MouseIsOver 封装，避免 secret 抛错导致卡死
local function safeIsVisible(region)
	local ok, v = pcall(function() return region:IsVisible() end)
	if ok and canAccessValueCompat(v) then return v end
	return false
end

local function safeMouseIsOver(region)
	local ok, v = pcall(function() return MouseIsOver(region) end)
	if ok and canAccessValueCompat(v) then return v end
	return false
end

--------------------------------------------------------------------------------
-- Search by font string (FIXED: 卡死 + 未找到文字)
--
-- 原版问题：
-- 1. IterateFrames() 遍历全UI所有Frame(重度UI可达 1万+)，每个GetRegions()都建表，同步阻塞主线程 = 你看到的卡死
-- 2. MouseIsOver(fontString) 是像素级命中，父Frame在鼠标下但FontString本身不在，必定 miss = 未找到文字
-- 3. 2026-01 重构删掉了 500 条限制，现在无论如何都会全量扫描
--
-- 修复：优先走 GetMouseFoci() 快速路径（仅检查鼠标下那几个Frame），失败再降级全量扫描并加限流
---@return string mouseoverText all text under the cursor.
function addon:GetMouseoverText()
	-- 聊天框特殊优先：ChatFrame 1-10 不在 GetMouseFoci 里也必须命中
	do
		for i = 1, 10 do
			local cf = _G["ChatFrame"..i]
			if cf and cf.GetMessageInfo then
				local okVis, isVis = pcall(function() return cf:IsVisible() end)
				local okOver, isOver = pcall(function() return MouseIsOver(cf) end)
				if okVis and okOver and isVis and isOver and canAccessValueCompat(isVis) and canAccessValueCompat(isOver) then
					local t = self:GetSpecificFrameText(cf)
					if t and t ~= "" then return t end
				end
			end
		end
		-- 再试 ChatFrame 的祖先：有些皮肤把聊天包在 ChatFrame1Tab / ChatFrame1Background 里
		if GetMouseFoci then
			local foci = GetMouseFoci()
			if foci then
				for _, f in ipairs(foci) do
					local cur = f
					for _ = 1, 5 do
						if not cur then break end
						if cur.GetMessageInfo and cur.GetNumMessages then
							local t = self:GetSpecificFrameText(cur)
							if t and t ~= "" then return t end
						end
						-- 名字匹配 ChatFrame*
						local n = cur:GetName()
						if n and n:find("^ChatFrame%d") then
							local cf = _G[n:match("^(ChatFrame%d)")]
							if cf then
								local t = self:GetSpecificFrameText(cf)
								if t and t ~= "" then return t end
							end
						end
						cur = cur:GetParent()
					end
				end
			end
		end
	end

	-- 任务列表等用宽松模式兜底
	local function tryChatAndQuestFast()
		local t = self:GetMouseFocusText()
		if t and t ~= "" then return t end
		t = self:GetMouseoverFramesText()
		if t and t ~= "" then return t end
	end
	local fast = tryChatAndQuestFast()
	if fast and fast ~= "" then return fast end

	-- 3. 精确 FontString 路径（适合零散文字）
	if GetMouseFoci then
		local foci = GetMouseFoci()
		if foci and #foci > 0 then
			local texts = {}
			for _, frame in ipairs(foci) do
				if frame ~= WorldFrame and not isAnchoringSecretCompat(frame) and not hasAnySecretAspectCompat(frame) then
					for fs in self:GetChildFontStrings(frame) do
						if safeIsVisible(fs) and safeMouseIsOver(fs) then
							local ok, txt = pcall(function() return fs:GetText() end)
							if ok and canAccessValueCompat(txt) and txt and txt ~= "" then
								texts[#texts+1] = txt
							end
						end
					end
					if #texts == 0 then
						local t = self:GetSpecificFrameText(frame)
						if t and t ~= "" then return t end
					end
				end
			end
			if texts[1] then
				return table.concat(texts, "\n")
			end
		end
	end

	-- 降级：全量扫描，之前 3000 阈值过低会误杀（你这张图实际只有几行字，但全UI有上万 FontString，扫到3000就被截断）
	-- 新逻辑：先尽力扫全量（上限放宽到50000），扫不到再自动降级到 mouseFocus / parentFrames
	local fontStringsIter = addon:GetDirectChildFontStrings(self:IterateFrames())
	local count = 0
	local MAX_CHECK = 50000
	local tooMany = false
	local function mouseoverFontStringsIter()
		local fontString = fontStringsIter()
		while fontString do
			count = count + 1
			if count > MAX_CHECK then
				tooMany = true
				break
			end
			if safeIsVisible(fontString) and safeMouseIsOver(fontString) then
				return fontString
			end
			fontString = fontStringsIter()
		end
	end
	local result = self:FontStringsToString(mouseoverFontStringsIter)
	if result then return result end
	if tooMany then
		-- 全量都扫到50000还没找到，说明 FontString 精确命中失败，自动用更宽松的模式兜底
		local fallback = self:GetMouseFocusText()
		if fallback and fallback ~= "" then return fallback end
		fallback = self:GetMouseoverFramesText()
		if fallback and fallback ~= "" then return fallback end
		addon:Print(L.tooManyFontStrings:format(MAX_CHECK))
	end
	return result
end

--------------------------------------------------------------------------------
-- Search by frame
--

do
	local blacklist = {
		UIParent = true,
		WorldFrame = true,
		WeakAurasFrame = true,
		DetailsAuraPanel = true,
		ElvUF_PetBattleFrameHider = true,
		TimerTracker = true,
		PetFrame = true,
	}

	setmetatable(blacklist, {
		__index = function(t, key)
			return type(key) == "string" and key:lower():find("parent")
		end,
	})

	---@return fun(): Frame? iter
	function addon:GetMouseoverFrames()
		local frameIter = self:IterateFrames()
		return function()
			local frame = frameIter()
			while frame do
				local status, isMouseOver = pcall(function()
					local parent = frame:GetParent()
					local isVisible = frame:IsVisible()
					local isMouseOver = not isAnchoringSecretCompat(frame)
						and not hasAnySecretAspectCompat(frame)
						and MouseIsOver(frame)
					local parentName = parent and parent:GetName()
					local name = frame:GetName()

					if canAccessAllValuesCompat(isVisible, isMouseOver, parentName, name) then
						return isVisible
							and isMouseOver
							and (parentName and blacklist[parentName] or parent == nil)
							and not blacklist[name]
					end
				end)
				if status and isMouseOver then
					return frame
				end
				frame = frameIter()
			end
		end
	end
end

---@return string containing all text from frames under the cursor.
function addon:GetMouseoverFramesText()
	local texts = {}
	for frame in self:GetMouseoverFrames() do
		texts[#texts + 1] = self:GetSpecificFrameText(frame)
	end
	return table.concat(texts, "\n")
end

--------------------------------------------------------------------------------
-- Search by mouse focus
--

---@return string
function addon:GetMouseFocusText()
	local frames
	if GetMouseFoci then
		frames = GetMouseFoci()
	else
		frames = { GetMouseFocus() }
	end
	local lines = {}
	for _, frame in next, frames do
		if frame ~= WorldFrame then
			-- 兼容聊天框：用 GetMessageInfo 而不是 FontString
			if frame.GetMessageInfo and frame:GetNumMessages() > 0 then
				local msgs = {}
				for i = 1, frame:GetNumMessages() do
					local msg = frame:GetMessageInfo(i)
					if canAccessValueCompat(msg) and msg and msg ~= "" then
						msgs[#msgs+1] = msg
					end
				end
				if msgs[1] then
					lines[#lines+1] = table.concat(msgs, "\n")
				else
					lines[#lines + 1] = self:GetSpecificFrameText(frame)
				end
			else
				lines[#lines + 1] = self:GetSpecificFrameText(frame)
			end
		end
	end
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Search tooltip
--

---@return string?
function addon:GetTooltipText()
	for frame in self:IterateFrames() do
		if frame.GetObjectType and frame:GetObjectType() == "GameTooltip" and frame:IsShown() then
			local text = self:GetSpecificFrameText(frame)
			if text then
				return text
			end
		end
	end
	if GameTooltip and GameTooltip:IsShown() then
		return self:GetSpecificFrameText(GameTooltip)
	end
end

--------------------------------------------------------------------------------
-- Specific frame
--

---@param frame Frame
---@return string
function addon:GetSpecificFrameText(frame)
	-- 聊天框特殊处理（原版在 ab1e041 被误删，导致聊天无法复制）
	if frame.GetMessageInfo and frame.GetNumMessages then
		local ok, n = pcall(function() return frame:GetNumMessages() end)
		if ok and n and n > 0 then
			local msgs = {}
			for i = 1, n do
				local ok2, msg = pcall(function() return frame:GetMessageInfo(i) end)
				if ok2 and canAccessValueCompat(msg) and msg and msg ~= "" then
					msgs[#msgs+1] = msg
				end
			end
			if msgs[1] then return table.concat(msgs, "\n") end
		end
	end

	local fontStringIter = addon:GetChildFontStrings(frame)
	local function visibleFontStrings()
		local fontString = fontStringIter()
		while fontString do
			if safeIsVisible(fontString) then
				return fontString
			end
			fontString = fontStringIter()
		end
	end
	return addon:FontStringsToString(visibleFontStrings)
end

--------------------------------------------------------------------------------
-- Helper functions
--

---@param fontStringsIter fun(): FontString?
---@return string
function addon:FontStringsToString(fontStringsIter)
	local texts = {}
	for fontString in fontStringsIter do
		local ok, text = pcall(function() return fontString:GetText() end)
		if ok and canAccessValueCompat(text) and text and text ~= "" then
			texts[#texts + 1] = text
		end
	end
	return texts[1] and table.concat(texts, "\n")
end

do
	---@param frame Frame Frame to scan recirsively for children.
	---@return fun(): Frame? iter
	local function GetChildrenRecursive(frame)
		return coroutine.wrap(function()
			local ok, children = pcall(function() return { frame:GetChildren() } end)
			if not ok or not children then return end
			local count = #children
			for i = 1, count do
				local child = children[i]
				-- secret frame 直接跳过，避免 polluted
				local ok2, isSecret = pcall(function() return hasAnySecretAspectCompat(child) or isAnchoringSecretCompat(child) end)
				if not ok2 or not isSecret then
					coroutine.yield(child)
					for subChild in GetChildrenRecursive(child) do
						coroutine.yield(subChild)
					end
				end
			end
		end)
	end

	---@param frame Frame to scan for font strings.
	---@return fun(): FontString? iter Iterator of FontStrings
	function addon:GetChildFontStrings(frame)
		local childFramesIter = GetChildrenRecursive(frame)
		local framesIter = coroutine.wrap(function()
			coroutine.yield(frame)
			for childFrame in childFramesIter do
				coroutine.yield(childFrame)
			end
		end)
		local fontStrings = self:GetDirectChildFontStrings(framesIter)
		return fontStrings
	end
end

-- Returns font strings that are a direct child of any of the supplied frames.
---@param framesIter fun(): Frame? frames to search.
---@return fun(): FontString? iter FontStrings that are direct children of the supplied frames.
function addon:GetDirectChildFontStrings(framesIter)
	return coroutine.wrap(function()
		for frame in framesIter do
			local ok, regions = pcall(function() return { frame:GetRegions() } end)
			if ok and regions then
				for _, region in next, regions do
					if region.GetText then
						coroutine.yield(region)
					end
				end
			end
		end
	end)
end

---@return fun(): Frame? iter
function addon:IterateFrames()
	local frame = nil
	return function()
		frame = EnumerateFrames(frame)
		return frame
	end
end
