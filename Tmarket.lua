script_name("Tmarket")
script_author("legacy")
script_version("1.40")

local fa = require('fAwesome6_solid')
local imgui = require 'mimgui'
local encoding = require 'encoding'
local ffi = require('ffi')
local dlstatus = require("moonloader").download_status
local effil = require("effil")
local json = require("json")
local iconv = require("iconv")

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local settingsPath = getWorkingDirectory() .. '\\config\\settings.json'

local windowSettings = {
    x = nil,
    y = nil,
    w = nil,
    h = nil,
    buyVc = 1,
    sellVc = 1,
    customCsvURL = "",
}

local function loadSettings()
    local f = io.open(settingsPath, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, data = pcall(json.decode, content)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do
                if k ~= "expirationDate" then
                    windowSettings[k] = v
                end
            end
        end
    end
end

local function saveSettings()
    local f = io.open(settingsPath, "w+")
    if f then
        local settingsToSave = {}
        for k, v in pairs(windowSettings) do
            if k ~= "expirationDate" then
                settingsToSave[k] = v
            end
        end
        f:write(json.encode(settingsToSave))
        f:close()
    end
end

loadSettings()

local updateInfoUrl = "https://raw.githubusercontent.com/Flashlavka/ssss/refs/heads/main/update.json"
local csvURL = nil
local allowedNicknames = {}
local currentExpirationDate = ""

local renderWindow = imgui.new.bool(false)
local showSettings = imgui.new.bool(false)
local sheetData = nil
local lastGoodSheetData = nil
local isLoading = false
local firstLoadComplete = false
local searchInput = ffi.new("char[128]", "")

local buyVcInput = ffi.new("float[1]", windowSettings.buyVc)
local sellVcInput = ffi.new("float[1]", windowSettings.sellVc)
local customCsvURLInput = ffi.new("char[512]", windowSettings.customCsvURL)

local function toLowerCyrillic(str)
    local map = {
        ["А"]="а",["Б"]="б",["В"]="в",["Г"]="г",["Д"]="д",["Е"]="е",["Ё"]="ё",["Ж"]="ж",["З"]="з",["И"]="и",
        ["Й"]="й",["К"]="к",["Л"]="л",["М"]="м",["Н"]="н",["О"]="о",["П"]="п",["Р"]="р",["С"]="с",["Т"]="т",
        ["У"]="у",["Ф"]="ф",["Х"]="х",["Ц"]="ц",["Ч"]="ч",["Ш"]="ш",["Щ"]="щ",["Ъ"]="ъ",["Ы"]="ы",["Ь"]="ь",
        ["Э"]="э",["Ю"]="ю",["Я"]="я"
    }
    for up, low in pairs(map) do str = str:gsub(up, low) end
    return str:lower()
end

local function versionToNumber(v)
    local clean = tostring(v):gsub("[^%d]", "")
    return tonumber(clean) or 0
end

local function checkExpiration(dateString)
    if not dateString then return true end
    local year, month, day = dateString:match("(%d%d%d%d)-(%d%d)-(%d%d)")
    if not (year and month and day) then return true end

    local currentTime = os.time(os.date("!*t"))
    
    local expirationTime = os.time{year=tonumber(year), month=tonumber(month), day=tonumber(day), hour=23, min=59, sec=59}

    return currentTime > expirationTime
end

local function isNicknameAllowed()
    local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    local rawNick = sampGetPlayerNickname(id)
    local currentNick = rawNick:match("%]%s*(.+)") or rawNick

    for i = 1, #allowedNicknames, 2 do
        local name = allowedNicknames[i]
        local date_string = allowedNicknames[i+1]
        if name and name == currentNick then
            currentExpirationDate = date_string
            if checkExpiration(date_string) then
                sampAddChatMessage(string.format("{FF0000}[Tmarket] {FFC800}%s{FFFFFF} срок действия скрипта истёк. Обратитесь к разработчику для продления.", currentNick), 0xFFFFFF)
                return false
            end
            return true
        end
    end
    sampAddChatMessage(string.format("{00FF00}[Tmarket] {FFC800}%s{FFFFFF} , вам доступ запрещён.", currentNick), -1)
    return false
end

local function checkForUpdates()
    local function asyncHttpRequest(method, url, args, resolve, reject)
        local thread = effil.thread(function(method, url, args)
            local requests = require("requests")
            local ok, response = pcall(requests.request, method, url, args)
            if ok then
                response.json, response.xml = nil, nil
                return true, response
            else
                return false, response
            end
        end)(method, url, args)

        lua_thread.create(function()
            while true do
                local status, err = thread:status()
                if not err then
                    if status == "completed" then
                        local ok, response = thread:get()
                        if ok then resolve(response) else reject(response) end
                        return
                    elseif status == "canceled" then
                        reject("Canceled")
                        return
                    end
                else
                    reject(err)
                    return
                end
                wait(0)
            end
        end)
    end

    asyncHttpRequest("GET", updateInfoUrl, nil, function(response)
        if response.status_code == 200 then
            local data = json.decode(response.text)
            if data then
                csvURL = data.csv
                allowedNicknames = data.nicknames or {}  
                local current = versionToNumber(thisScript().version)
                local remote = versionToNumber(data.version)
                if remote > current then
                    local tempPath = thisScript().path
                    local thread = effil.thread(function(url, tempPath)
                        local requests = require("requests")
                        local ok, response = pcall(requests.get, url)
                        if not ok or response.status_code ~= 200 then return false end
                        local f = io.open(tempPath, "wb")
                        if not f then return false end
                        f:write(response.text)
                        f:close()
                        return true
                    end)(data.url, tempPath)

                    lua_thread.create(function()
                        while true do
                            local status = thread:status()
                            if status == "completed" then
                                local ok = thread:get()
                                if ok then
                                    sampAddChatMessage("{00FF00}[Tmarket]{FFFFFF} Обновление загружено.", 0xFFFFFF)
                                end
                                return
                            elseif status == "canceled" then return end
                            wait(0)
                        end
                    end)
                end
            end
        end
    end, function(err) end)
end

local function theme()
    local s = imgui.GetStyle()
    local c = imgui.Col
    local clr = s.Colors
    s.WindowRounding = 0
    s.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    s.ChildRounding = 0
    s.FrameRounding = 5.0
    s.ItemSpacing = imgui.ImVec2(10, 10)
    clr[c.Text] = imgui.ImVec4(0.85, 0.86, 0.88, 1)
    clr[c.WindowBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.ChildBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.Button] = imgui.ImVec4(0.10, 0.15, 0.18, 1)
    clr[c.ButtonHovered] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.ButtonActive] = clr[c.ButtonHovered]
    clr[c.FrameBg] = imgui.ImVec4(0.10, 0.15, 0.18, 1)
    clr[c.FrameBgHovered] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.FrameBgActive] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.Separator] = imgui.ImVec4(0.20, 0.25, 0.30, 1)
    clr[c.TitleBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.TitleBgActive] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.TitleBgCollapsed] = imgui.ImVec4(0.05, 0.08, 0.10, 0.75)
    s.ScrollbarSize = 18
    s.ScrollbarRounding = 0
    s.GrabRounding = 0
    s.GrabMinSize = 38
    clr[c.ScrollbarBg] = imgui.ImVec4(0.04, 0.06, 0.07, 0.8)
    clr[c.ScrollbarGrab] = imgui.ImVec4(0.15, 0.15, 0.18, 1.0)
    clr[c.ScrollbarGrabHovered] = imgui.ImVec4(0.25, 0.25, 0.28, 1.0)
    clr[c.ScrollbarGrabActive] = imgui.ImVec4(0.35, 0.35, 0.38, 1.0)
end

imgui.OnInitialize(function()
    if MONET_DPI_SCALE == nil then MONET_DPI_SCALE = 1.0 end
    fa.Init(14 * MONET_DPI_SCALE)
    theme()
    imgui.GetIO().IniFilename = nil
end)

local function parseCSV(data)
    local rows = {}
    local ok, converted = pcall(function()
        local conv = iconv.new("CP1251", "UTF-8")
        return conv:iconv(data)
    end)
    if not ok then
        return nil
    end
    for line in converted:gmatch("[^\r\n]+") do
        local row, i, inQuotes, cell = {}, 1, false, ''
        for c in (line .. ','):gmatch('.') do
            if c == '"' then
                inQuotes = not inQuotes
            elseif c == ',' and not inQuotes then
                row[i] = cell:gsub('^%s*"(.-)"%s*$', '%1'):gsub('""', '"')
                i = i + 1
                cell = ''
            else
                cell = cell .. c
            end
        end
        table.insert(rows, row)
    end
    return rows
end

local function drawSpinner()
    local center = imgui.GetWindowPos() + imgui.GetWindowSize() * 0.5
    local radius, thickness, segments = 32.0, 3.0, 30
    local time = imgui.GetTime()
    local angle_offset = (time * 3) % (2 * math.pi)
    local drawList = imgui.GetWindowDrawList()
    for i = 0, segments - 1 do
        local a0 = i / segments * 2 * math.pi
        local a1 = (i + 1) / segments * 2 * math.pi
        local alpha = (i / segments)
        if alpha > 0.25 and alpha < 0.75 then
            local x0 = center.x + radius * math.cos(a0 + angle_offset)
            local y0 = center.y + radius * math.sin(a0 + angle_offset)
            local x1 = center.x + radius * math.cos(a1 + angle_offset)
            local y1 = center.y + radius * math.sin(a1 + angle_offset)
            drawList:AddLine(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1), imgui.GetColorU32(imgui.Col.Text), thickness)
        end
    end
end

local function CenterTextInColumn(text)
    local columnWidth = imgui.GetColumnWidth()
    local textWidth = imgui.CalcTextSize(text).x
    local wrapWidth = columnWidth * 0.8
    local offset = (columnWidth - math.min(textWidth, wrapWidth)) * 0.5
    if offset > 0 then imgui.SetCursorPosX(imgui.GetCursorPosX() + offset) end
    local cursorPosX = imgui.GetCursorPosX()
    imgui.PushTextWrapPos(cursorPosX + wrapWidth)
    imgui.TextWrapped(text)
    imgui.PopTextWrapPos()
end

local function CenterText(text)
    local windowWidth = imgui.GetWindowSize().x
    local textWidth = imgui.CalcTextSize(text).x
    local offset = (windowWidth - textWidth) * 0.5
    if offset > 0 then imgui.SetCursorPosX(offset) end
    imgui.TextWrapped(text)
end

local function formatNumberWithSpaces(n)
    local s = tostring(math.floor(n))
    local formatted = ""
    local count = 0
    for i = #s, 1, -1 do
        formatted = s:sub(i, i) .. formatted
        count = count + 1
        if count % 3 == 0 and i > 1 then
            formatted = " " .. formatted
        end
    end
    return formatted
end

local function drawTable(data)
    if isLoading or not firstLoadComplete or not data then
        drawSpinner()
        imgui.Dummy(imgui.ImVec2(0, 40))
        CenterText(u8"Загрузка таблицы...")
        return
    end

    if #data == 0 then return end

    local filter = toLowerCyrillic(u8:decode(ffi.string(searchInput)))
    local filtered = {}

    table.insert(filtered, data[1])
    for i = 2, #data do
        local row = data[i]
        local match = false
        for _, cell in ipairs(row) do
            if toLowerCyrillic(tostring(cell)):find(filter, 1, true) then
                match = true break
            end
        end
        if match then table.insert(filtered, row) end
    end

    imgui.BeginChild("scrollingRegion", imgui.ImVec2(-1, -1), true)

    if #filtered == 1 and filter ~= "" then
        CenterText(u8"Совпадений нет.")
        imgui.EndChild()
        return
    end

    local regionWidth = imgui.GetContentRegionAvail().x
    local columnWidth = regionWidth / 3
    local pos = imgui.GetCursorScreenPos()
    local y0 = pos.y - imgui.GetStyle().ItemSpacing.y
    local y1 = pos.y + imgui.GetWindowSize().y - imgui.GetCursorPosY() - imgui.GetStyle().WindowPadding.y * 2

    local x1 = pos.x + columnWidth
    local x2 = pos.x + 2 * columnWidth

    local draw = imgui.GetWindowDrawList()
    local sepColor = imgui.GetColorU32(imgui.Col.Separator)
    draw:AddLine(imgui.ImVec2(x1, y0), imgui.ImVec2(x1, y1), sepColor, 1)
    draw:AddLine(imgui.ImVec2(x2, y0), imgui.ImVec2(x2, y1), sepColor, 1)

    imgui.Columns(3, nil, false)
    for i = 1, 3 do
        CenterTextInColumn(u8(tostring(filtered[1][i] or "")))
        imgui.NextColumn()
    end
    imgui.Separator()

    local currentBuyVc = buyVcInput[0]
    local currentSellVc = sellVcInput[0]

    for i = 2, #filtered do
        for col = 1, 3 do
            local cellValue = tostring(filtered[i][col] or "")
            if col == 2 then
                local numStr = cellValue:gsub("[^%d%.%-]+", "")
                local num = tonumber(numStr)
                if num then
                    cellValue = formatNumberWithSpaces(num * currentBuyVc)
                end
            elseif col == 3 then
                local numStr = cellValue:gsub("[^%d%.%-]+", "")
                local num = tonumber(numStr)
                if num then
                    cellValue = formatNumberWithSpaces(num * currentSellVc)
                end
            end
            CenterTextInColumn(u8(cellValue))
            imgui.NextColumn()
        end
        imgui.Separator()
    end

    imgui.Columns(1)
    imgui.EndChild()
end

local function extractGoogleSheetIds(googleSheetUrl)
    local spreadsheetId = googleSheetUrl:match("/d/([a-zA-Z0-9_-]+)")
    local gid = googleSheetUrl:match("gid=(%d+)") or "0"
    return spreadsheetId, gid
end

local function updateCSV()
    local urlToUse = csvURL
    if windowSettings.customCsvURL and windowSettings.customCsvURL ~= "" then
        local customUrl = windowSettings.customCsvURL
        local spreadsheetId, gid = extractGoogleSheetIds(customUrl)
        if spreadsheetId then
            urlToUse = string.format("https://docs.google.com/spreadsheets/d/%s/gviz/tq?tqx=out:csv&gid=%s", spreadsheetId, gid)
        else
            urlToUse = customUrl
        end
    end

    if not urlToUse then return end

    isLoading = true
    firstLoadComplete = false
    local tmpPath = os.tmpname() .. ".csv"
    downloadUrlToFile(urlToUse, tmpPath, function(success)
        if success then
            local f = io.open(tmpPath, "rb")
            if f then
                local content = f:read("*a")
                f:close()
                sheetData = parseCSV(content)
                if sheetData then
                    lastGoodSheetData = sheetData
                else
                    sheetData = lastGoodSheetData
                end
                os.remove(tmpPath)
            else
                sheetData = lastGoodSheetData
            end
        else
            sheetData = lastGoodSheetData
        end
        isLoading = false
        firstLoadComplete = true
    end)
end

imgui.OnFrame(function() return renderWindow[0] end, function()
    local sx, sy = getScreenResolution()
    local w = windowSettings.w or math.min(900, sx - 50)
    local h = windowSettings.h or 500
    local x = windowSettings.x or (sx - w) / 2
    local y = windowSettings.y or (sy - h) / 2
    imgui.SetNextWindowPos(imgui.ImVec2(x, y), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.FirstUseEver)

    if imgui.Begin(string.format("Tmarket %s", thisScript().version), renderWindow) then
        local availWidth = imgui.GetContentRegionAvail().x

        local function iconButton(icon, tooltip, action)
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.15, 0.20, 0.23, 0.3))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.15, 0.20, 0.23, 0.5))
            if imgui.SmallButton(icon) then action() end
            imgui.PopStyleColor(3)
            if imgui.IsItemHovered() then imgui.SetTooltip(tooltip) end
        end

        if showSettings[0] then
            iconButton(fa.ARROW_LEFT, u8"Назад к таблице", function()
                showSettings[0] = false
            end)
            imgui.SameLine()
        else
            imgui.PushItemWidth(availWidth * 0.75)
            imgui.InputTextWithHint("##search", u8"Поиск по таблице...", searchInput, ffi.sizeof(searchInput))
            imgui.PopItemWidth()

            imgui.SameLine()
            iconButton(fa.ERASER, u8"Очистить поиск", function()
                ffi.fill(searchInput, ffi.sizeof(searchInput))
            end)

            imgui.SameLine()
            iconButton(fa.ROTATE, u8"Обновить таблицу", function()
                updateCSV()
            end)

            imgui.SameLine()
            iconButton(fa.GEARS, u8"Настройки", function()
                showSettings[0] = not showSettings[0]
            end)
        end

        imgui.Spacing()

        if showSettings[0] then
            CenterText(u8"Settings legacy script <3")
            imgui.Text(u8"Курс множителя цен в таблице")
            imgui.Separator()

            local function inputMultiplier(label, var)
                local formatStr = (var[0] == math.floor(var[0])) and "%.0f" or "%.2f"
                imgui.PushItemWidth(availWidth * 0.2)
                imgui.InputFloat(label, var, 0.0, 0.0, formatStr)
                imgui.PopItemWidth()
            end

            inputMultiplier(u8"Курс покупки VC$", buyVcInput)
            windowSettings.buyVc = buyVcInput[0]

            inputMultiplier(u8"Курс продажи VC$", sellVcInput)
            windowSettings.sellVc = sellVcInput[0]

            imgui.Spacing()
            imgui.Separator()


            imgui.Text(u8"Пользовательская ссылка на CSV-таблицу:")
            imgui.PushItemWidth(availWidth * 0.8)
            imgui.InputTextWithHint("##customCsvURL", u8"Вставьте ссылку на Google Таблицу...", customCsvURLInput, ffi.sizeof(customCsvURLInput))
            windowSettings.customCsvURL = u8:decode(ffi.string(customCsvURLInput))
            imgui.PopItemWidth()
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Ваша ссылка на Google Таблицу. Если поле пустое, будет использоваться ссылка по умолчанию.") end

            imgui.SameLine()
            iconButton(fa.TRASH_CAN, u8"Очистить ссылку", function()
                ffi.fill(customCsvURLInput, ffi.sizeof(customCsvURLInput))
                windowSettings.customCsvURL = ""
            end)

            CenterText(u8"Как использовать Google Таблицу в скрипте:")
            imgui.Text(u8"1 - Если у вас уже есть ссылка на открытую Google Таблицу,просто скопируйте её и вставьте в поле ниже.")
            imgui.Text(u8"2 - Если таблица закрытая, откройте её в Google Sheets и опубликуйте в интернете")
            imgui.Text(u8"3 - Меню: Файл > Опубликовать в интернете")
            imgui.Text(u8"4 - Скопируйте ссылку публикации и вставьте в поле скрипта.")
            imgui.Text(u8"5 - После вставки нажмите «Обновить таблицу» для загрузки данных.")
            imgui.Text(u8"6 - Скрипт автоматически преобразует обычные ссылки из адресной строки.")
            imgui.Text(u8"7 - Убедитесь, что таблица доступна по ссылке для корректной загрузки.")
            imgui.Text(u8"8 - P.s пжшка, учтите, если таблица закрыта и не опубликована, данные с таблицы не будут загружены")
            imgui.Separator()

            if currentExpirationDate and currentExpirationDate ~= "" then
                imgui.Text(u8("Последний день подписки: ") .. u8(currentExpirationDate))
            else
                imgui.Text(u8"Информация о подписке недоступна.")
            end
            imgui.Spacing()
            imgui.Separator()

        else
            drawTable(sheetData)
        end

        local pos, size = imgui.GetWindowPos(), imgui.GetWindowSize()
        windowSettings.x, windowSettings.y = pos.x, pos.y
        windowSettings.w, windowSettings.h = size.x, size.y
        saveSettings()
    else
        local pos, size = imgui.GetWindowPos(), imgui.GetWindowSize()
        windowSettings.x, windowSettings.y = pos.x, pos.y
        windowSettings.w, windowSettings.h = size.x, size.y
        saveSettings()
    end
end)


function main()
    while not isSampAvailable() do wait(0) end

    checkForUpdates()

    while #allowedNicknames == 0 do wait(0) end  

    if not isNicknameAllowed() then
        return
    end

    sampAddChatMessage("{00FF00}[Tmarket]{FFFFFF} Скрипт загружен. Для активации используйте {00FF00}/tm", 0xFFFFFF)

    sampRegisterChatCommand('tm', function()
        renderWindow[0] = not renderWindow[0]
        if renderWindow[0] and not firstLoadComplete and not showSettings[0] then
            updateCSV()
        end
    end)

    wait(-1)
end