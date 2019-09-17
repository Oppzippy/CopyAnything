_G['SLASH_COPY1'] = '/copyanything'
_G['SLASH_COPY2'] = '/copy'

local EnumerateFrames = EnumerateFrames

local function GetFontStrings(condition)
    local fontStrings = {}
    local frame = EnumerateFrames()
    while frame do
        if frame:GetNumRegions() >= 1 then
            local regions = { frame:GetRegions() }
            for i, region in next, regions do
                if region:GetObjectType() == "FontString" and condition(region) then
                    fontStrings[#fontStrings+1] = region
                end
            end
        end
        frame = EnumerateFrames(frame)
    end
    return fontStrings
end

SlashCmdList['COPY'] = function()
    local t = debugprofilestop()
    local frames = GetFontStrings(function(f)
        return MouseIsOver(f) and f:IsVisible()
    end)
    print(debugprofilestop()-t)
    local texts = {}
    for i, f in ipairs(frames) do
        texts[i] = f:GetText()
    end
    LibStub('LibCopyPaste-1.0'):Copy('Copy Anything', table.concat(texts, '\n'))
end
