-- ================================
--   Auto Collect Core v4.1
-- ================================

local config = _G.config

local state = {
    running   = true,
    dropping  = false,
    collected = 0,
    last_tile = { x = -1, y = -1 },
}

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

local function log(msg)
    LogToConsole('`2[AutoCollect] `7' .. msg)
end

local function getDynamicDelay(dist)
    local maxDist = 20.0
    local t = math.min(dist / maxDist, 1.0)
    return math.floor(config.walk_delay_max - (config.walk_delay_max - config.walk_delay_min) * t)
end

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
