_G['SLASH_COPY1'] = '/copyanything'
_G['SLASH_COPY2'] = '/copy'

local EnumerateFrames, MouseIsOver = EnumerateFrames, MouseIsOver

local function GetFontStrings(condition)
    local fontStrings = {}
    local frame = EnumerateFrames()
    while frame do
        local regions = { frame:GetRegions() }
        for i, region in next, regions do
            -- much faster to check if GetText than to use GetObjectType and check if FontString
            if region.GetText and condition(region) then
                fontStrings[#fontStrings+1] = region
            end
        end
        frame = EnumerateFrames(frame)
    end
    return fontStrings
end

local function FilterFontString(fontString)
    return fontString:IsVisible() and MouseIsOver(fontString)
end

local function CopyText()
    local frames = GetFontStrings(FilterFontString)
    local texts = {}
    for i, f in ipairs(frames) do
        texts[i] = f:GetText()
    end
    LibStub('LibCopyPaste-1.0'):Copy('Copy Anything', table.concat(texts, '\n'))
end

SlashCmdList['COPY'] = CopyText
