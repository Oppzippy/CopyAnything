local L = LibStub("AceLocale-3.0"):NewLocale("CopyAnything", "ruRU")
if not L then return end

--@localization(locale="ruRU", handle-unlocalized="comment")@
-- Translator ZamestoTV
--@do-not-package@
-- General
L.copyAnything = "Копировать всё"

-- Bindings
L.show = "Показать"

-- Options
L.general = "Общие"
L.profiles = "Профили"
L.copyFrame = "Копировать фрейм"
L.fastCopy = "Быстрое копирование"
L.fastCopyDesc = "Автоматически скрывать фрейм копирования после нажатия CTRL+C."

-- Search types
L.searchType = "Тип поиска"
L.searchTypeDesc = "Метод поиска фреймов под курсором."
L.searchTypeDescExtended = [=[Строки шрифта (по умолчанию) - Поиск отдельных строк шрифта под курсором.
Родительские фреймы - Поиск верхнеуровневых фреймов под курсором и копирование всего текста из их дочерних элементов.
Фокус мыши - Копирование текста из фрейма, находящегося в фокусе мыши. Работает только с фреймами, зарегистрированными для событий мыши.]=]
L.fontStrings = "Строки шрифта"
L.parentFrames = "Родительские фреймы"
L.mouseFocus = "Фокус мыши"

-- Errors
L.invalidSearchType = "Неверный тип поиска '%s'. Проверьте настройки."
L.noTextFound = "Текст не найден."
L.tooManyFontStrings = "Найдено более %d строк шрифта. Копирование отменено, чтобы предотвратить зависание игры на длительное время."
--@end-do-not-package@
