-- =================================================================
-- CORE LOGIC - HOSTED ON GITHUB (Bebas dari Eror Struktur)
-- =================================================================

local function cetakLog(teks)
    if log then log(teks) elseif print then print(teks) end
end

function AmbilJumlahInventory(item_id)
    local sukses, hasil = pcall(function()
        if GetInventory then
            for _, item in pairs(GetInventory()) do
                if item and item.id == item_id then
                    return item.count or 0
                end
            end
        end
        return 0
    end)
    return sukses and hasil or 0
end

function JalanKeTile(x, y)
    local sukses = pcall(function()
        if FindPath then FindPath(x, y) elseif MoveTo then MoveTo(x, y) end
    end)
    Sleep(1200) 
    return sukses
end

function DapatkanKoordinatAman()
    local x = _G.DROP_X
    local y = _G.DROP_Y
    if not GetTile then return x, y end

    local tileDepan = GetTile(x + 1, y)
    if tileDepan and tileDepan.id ~= 0 then
        cetakLog("[ALERT] Jalur depan terhalang! Menggeser ke belakang...")
        return x - 1, y
    end

    local tileBelakang = GetTile(x - 1, y)
    if tileBelakang and tileBelakang.id ~= 0 then
        cetakLog("[ALERT] Jalur belakang terhalang! Menggeser ke depan...")
        return x + 1, y
    end
    return x, y
end

function JalankanDropItem()
    cetakLog("[SISTEM] Inventory penuh. Menghitung jalur drop aman...")
    local amanX, amanY = DapatkanKoordinatAman()
    JalanKeTile(amanX, amanY)
    Sleep(500)
    
    local jumlahSekarang = AmbilJumlahInventory(_G.TARGET_ITEM_ID)
    if jumlahSekarang > 0 then
        cetakLog("[DROP] Membuang " .. jumlahSekarang .. "x Item di tile: (" .. amanX .. ", " .. amanY .. ")")
        pcall(function()
            if Drop then Drop(_G.TARGET_ITEM_ID, jumlahSekarang)
            elseif SendDropPacket then SendDropPacket(_G.TARGET_ITEM_ID, jumlahSekarang) end
        end)
        Sleep(1500) 
    end
end

-- MAIN LOOP
cetakLog("[START] Core Script terintegrasi penuh.")
while true do
    local statusBot = "Online"
    if bot and bot.status then statusBot = bot.status
    elseif getBot then statusBot = getBot().status or statusBot end
    
    if statusBot == "Online" then
        if AmbilJumlahInventory(_G.TARGET_ITEM_ID) >= 200 then
            JalankanDropItem()
        else
            local itemDitemukan = false
            pcall(function()
                if GetObjects then
                    for _, obj in pairs(GetObjects()) do
                        if obj and obj.id == _G.TARGET_ITEM_ID then
                            itemDitemukan = true
                            local tileX = math.floor(obj.x / 32)
                            local tileY = math.floor(obj.y / 32)
                            cetakLog("[NAVIGASI] Menuju item di tile: ("..tileX..", "..tileY..")")
                            JalanKeTile(tileX, tileY)
                            break 
                        end
                    end
                end
            end)
            
            if not itemDitemukan then
                cetakLog("[INFO] Semua objek dengan ID " .. _G.TARGET_ITEM_ID .. " selesai dibersihkan.")
                if AmbilJumlahInventory(_G.TARGET_ITEM_ID) > 0 then JalankanDropItem() end
                break 
            end
        end
    else
        cetakLog("[WARNING] Bot Offline. Menunggu tersambung...")
        Sleep(5000)
    end
    Sleep(800) 
end
cetakLog("[FINISH] Script berhenti dengan sukses.")
