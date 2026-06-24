-- ================================
--   Auto Buy Vend Core v1.1
--   Bothax Lua Script
-- ================================

local config = _G.config

local state = {
    running      = true,
    phase        = 'warp_vend',
    bought       = 0,
    dialog_ready = false,
    dialog_text  = '',
}

local function log(msg)
    LogToConsole('`2[AutoBuy] `7' .. msg)
end

local function getItemCount()
    for _, item in pairs(GetInventory()) do
        if item.id == config.item_id then
            return item.amount
        end
    end
    return 0
end

local function getItemName(id)
    local info = GetItemByIDSafe(id)
    return info and info.name or ('ID:' .. id)
end

local function isDisconnected()
    local client = GetClient()
    local world = GetWorld()
    if client and client.ping >= 999 then return true end
    if world == nil then return true end
    return false
end

local function waitWorld(worldName, timeoutMs)
    timeoutMs = timeoutMs or 15000
    local elapsed = 0
    while elapsed < timeoutMs do
        local w = GetWorld()
        if w and w.name:upper() == worldName:upper() then
            return true
        end
        Sleep(500)
        elapsed = elapsed + 500
    end
    return false
end

local function walkToward(targetX, targetY)
    local lp = GetLocal()
    if not lp then return false end

    local px = math.floor(lp.pos.x / 32)
    local py = math.floor(lp.pos.y / 32)

    if px == targetX and py == targetY then return true end

    local dx = targetX - px
    local dy = targetY - py
    local nextX = px + (dx ~= 0 and (dx > 0 and 1 or -1) or 0)
    local nextY = py + (dy ~= 0 and (dy > 0 and 1 or -1) or 0)

    if CheckPath(nextX, nextY) then
        FindPath(nextX, nextY)
    end

    return false
end

local function walkTo(targetX, targetY, timeoutMs)
    timeoutMs = timeoutMs or 20000
    local elapsed = 0

    while state.running do
        if walkToward(targetX, targetY) then return true end
        Sleep(config.walk_delay)
        elapsed = elapsed + config.walk_delay
        if elapsed >= timeoutMs then
            log('Timeout jalan ke (' .. targetX .. ',' .. targetY .. ')')
            return false
        end
        local lp = GetLocal()
        if lp then
            if math.floor(lp.pos.x / 32) == targetX and
               math.floor(lp.pos.y / 32) == targetY then
                return true
            end
        end
    end
    return false
end

-- Wrench tile untuk buka dialog vend
local function wrenchTile(x, y)
    SendPacketRaw(false, {
        type  = 3,
        value = 32,  -- wrench
        px    = x,
        py    = y,
        x     = x * 32,
        y     = y * 32,
    })
end

-- Hook tangkap dialog vend
AddHook('OnVariant', 'AutoBuyDialog', function(var)
    if var[0] == 'OnDialogRequest' then
        local text = var[1] or ''
        if text:find('vend') or text:find('store_item') or text:find('buy_item') then
            state.dialog_ready = true
            state.dialog_text  = text
            log('Dialog vend tertangkap!')
            return true
        end
    end
end)

local function getDialogName(text)
    return text:match('end_dialog|([^|]+)') or 'vending_store'
end

local function buyFromDialog()
    if not state.dialog_ready then return false end

    local dname = getDialogName(state.dialog_text)
    log('Beli dari dialog: ' .. dname)

    SendPacket(2, 'action|dialog_return\ndialog_name|' .. dname .. '\nbuttonClicked|buy')
    Sleep(config.action_delay)

    state.dialog_ready = false
    state.dialog_text  = ''
    return true
end

local function dropItem()
    local count = getItemCount()
    if count > 0 then
        SendPacket(2, 'action|drop\n|itemid|' .. config.item_id)
        Sleep(config.action_delay)
        log('Drop ' .. count .. 'x ' .. getItemName(config.item_id) .. ' berhasil!')
        state.bought = state.bought + count
    end
end

-- ======= MAIN LOOP =======

local function mainLoop()
    log('Mulai! Target: `6' .. getItemName(config.item_id) ..
        ' `7| Vend: `6' .. config.vend_world ..
        ' `7| Storage: `6' .. config.storage_world)

    while state.running do

        if isDisconnected() then
            log('`4Disconnect! Tunggu ' .. (config.reconnect_delay/1000) .. ' detik...')
            Sleep(config.reconnect_delay)
            state.phase = 'warp_vend'
        end

        -- FASE: WARP KE VEND
        if state.phase == 'warp_vend' then
            log('Warp ke: `6' .. config.vend_world)
            RequestJoinWorld(config.vend_world)
            Sleep(config.warp_delay)

            if waitWorld(config.vend_world, 10000) then
                log('Masuk `6' .. config.vend_world)
                Sleep(config.action_delay)
                state.phase = 'walk_vend'
            else
                log('`4Gagal masuk vend world, retry...')
                Sleep(3000)
            end

        -- FASE: JALAN KE VEND
        elseif state.phase == 'walk_vend' then
            log('Jalan ke vend (' .. config.vend_x .. ',' .. config.vend_y .. ')...')

            if walkTo(config.vend_x, config.vend_y, 20000) then
                Sleep(500)
                state.phase = 'buy'
            else
                log('`4Gagal jalan ke vend, warp ulang...')
                state.phase = 'warp_vend'
            end

        -- FASE: BELI ITEM
        elseif state.phase == 'buy' then
            log('Wrench vend...')
            state.dialog_ready = false

            wrenchTile(config.vend_x, config.vend_y)
            Sleep(config.action_delay)

            -- Tunggu dialog max 3 detik
            local waited = 0
            while not state.dialog_ready and waited < 3000 do
                Sleep(200)
                waited = waited + 200
            end

            if state.dialog_ready then
                buyFromDialog()
                Sleep(config.action_delay)

                local count = getItemCount()
                log('Inventory: `6' .. count .. '/' .. config.buy_amount)

                if count >= config.buy_amount then
                    state.phase = 'warp_storage'
                end
            else
                log('`4Dialog tidak muncul, wrench ulang...')
                Sleep(1000)
            end

        -- FASE: WARP KE STORAGE
        elseif state.phase == 'warp_storage' then
            log('Inventory penuh! Warp ke: `6' .. config.storage_world)
            RequestJoinWorld(config.storage_world)
            Sleep(config.warp_delay)

            if waitWorld(config.storage_world, 10000) then
                log('Masuk `6' .. config.storage_world)
                Sleep(config.action_delay)
                state.phase = 'drop'
            else
                log('`4Gagal masuk storage, retry...')
                Sleep(3000)
            end

        -- FASE: DROP ITEM
        elseif state.phase == 'drop' then
            log('Jalan ke drop point (' .. config.storage_x .. ',' .. config.storage_y .. ')...')

            if walkTo(config.storage_x, config.storage_y, 20000) then
                Sleep(500)
                dropItem()
                log('Total terkumpul: `6' .. state.bought .. ' item')
                Sleep(config.action_delay)
                state.phase = 'warp_vend'
            else
                log('`4Gagal jalan ke drop point, retry...')
            end
        end

        Sleep(300)
    end

    log('Selesai. Total: `6' .. state.bought .. ' item terbeli.')
end

RunThread(mainLoop)
local function walkToward(targetX, targetY)
    local lp = GetLocal()
    if not lp then return false, 0 end

    local px = math.floor(lp.pos.x / 32)
    local py = math.floor(lp.pos.y / 32)

    if px == targetX and py == targetY then return true, 0 end

    local dx = targetX - px
    local dy = targetY - py
    local dist = math.sqrt(dx * dx + dy * dy)

    local nextX = px + (dx ~= 0 and (dx > 0 and 1 or -1) or 0)
    local nextY = py + (dy ~= 0 and (dy > 0 and 1 or -1) or 0)

    if CheckPath(nextX, nextY) then
        FindPath(nextX, nextY)
        Sleep(config.walk_delay_min)
    else
        log('Tile (' .. nextX .. ',' .. nextY .. ') blocked, skip.')
    end

    return false, dist
end

local function walkTo(targetX, targetY, timeoutMs)
    timeoutMs = timeoutMs or 30000
    local elapsed = 0

    while state.running do
        local done, dist = walkToward(targetX, targetY)
        if done then return true end

        local delay = getDynamicDelay(dist)
        Sleep(delay)
        elapsed = elapsed + delay + config.walk_delay_min

        if elapsed >= timeoutMs then
            log('Timeout jalan ke (' .. targetX .. ',' .. targetY .. '), skip.')
            return false
        end

        local lp = GetLocal()
        if lp then
            if math.floor(lp.pos.x / 32) == targetX and math.floor(lp.pos.y / 32) == targetY then
                return true
            end
        end
    end
    return false
end

local function doDropItem()
    state.dropping = true
    log('Inventory penuh! Jalan ke drop point (' .. config.drop_x .. ',' .. config.drop_y .. ')...')

    if walkTo(config.drop_x, config.drop_y, 30000) then
        Sleep(500)
        local count = getItemCount()
        if count > 0 then
            SendPacket(2, 'action|drop\n|itemid|' .. config.item_id)
            state.collected = state.collected + count
            log('Drop ' .. count .. 'x ' .. getItemName(config.item_id) .. ' berhasil! Total: ' .. state.collected)
            Sleep(800)
        end
    end

    state.dropping = false
end

local function collectLoop()
    state.collected = 0
    log('Mulai! Target: `6' .. getItemName(config.item_id) ..
        ' `7| Max: `6' .. config.max_amount ..
        ' `7| Drop: `6(' .. config.drop_x .. ',' .. config.drop_y .. ')')
    log('Walk delay: `6' .. config.walk_delay_min .. 'ms `7- `6' .. config.walk_delay_max .. 'ms `7(dynamic)')

    while state.running do
        if getItemCount() >= config.max_amount then
            doDropItem()
        else
            local lp = GetLocal()
            if lp then
                local px = lp.pos.x / 32
                local py = lp.pos.y / 32
                local nearest, nearestDist = nil, 999999

                for _, obj in pairs(GetObjectList()) do
                    if obj.id == config.item_id then
                        local tx = obj.pos.x / 32
                        local ty = obj.pos.y / 32
                        local dist = math.sqrt((tx - px)^2 + (ty - py)^2)
                        if dist < nearestDist then
                            local tileX = math.floor(tx)
                            local tileY = math.floor(ty)
                            if CheckPath(tileX, tileY) then
                                nearestDist = dist
                                nearest = { x = tileX, y = tileY }
                            end
                        end
                    end
                end

                if nearest then
                    if nearest.x ~= state.last_tile.x or nearest.y ~= state.last_tile.y then
                        state.last_tile = { x = nearest.x, y = nearest.y }
                        log('Jalan ke item (' .. nearest.x .. ',' .. nearest.y .. ') | delay=' .. getDynamicDelay(nearestDist) .. 'ms')
                    end
                    walkTo(nearest.x, nearest.y, 30000)
                    Sleep(100)
                else
                    Sleep(config.scan_delay)
                end
            else
                Sleep(config.scan_delay)
            end
        end
    end

    log('Selesai. Total terkumpul: `6' .. state.collected .. ' item.')
end

RunThread(collectLoop)
