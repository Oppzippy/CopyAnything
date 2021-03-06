local L = LibStub("AceLocale-3.0"):NewLocale("CopyAnything", "enUS", true)

--@localization(locale="enUS", handle-unlocalized="comment")@

--@do-not-package@
-- General
L.copyAnything = "Copy Anything"

-- Bindings
L.show = "Show"

-- Options
L.general = "General"
L.profiles = "Profiles"
L.copyFrame = "Copy Frame"
L.fastCopy = "Fast Copy"
L.fastCopyDesc = "Automatically hide the copy frame after CTRL+C is pressed."

-- Search types
L.searchType = "Search Type"
L.searchTypeDesc = "Method to use for searching for frames under the cursor."
L.searchTypeDescExtended = [=[Font Strings (default) - Search for individual FontStrings under the cursor.
Parent Frames - Search for top level frames under the cursor, and copy all text from their children.
Mouse Focus - Copy text from the mouse focus frame. Only works on frames that are registered for mouse events.]=]
L.fontStrings = "Font Strings"
L.parentFrames = "Parent Frames"
L.mouseFocus = "Mouse Focus"

-- Errors
L.invalidSearchType = "Invalid search type '%s'. Check options."
L.noTextFound = "No text found."
L.tooManyFontStrings = "More than %d font strings were found. The copy was cancelled to prevent the game from freezing for an excessive amount of time."
--@end-do-not-package@
