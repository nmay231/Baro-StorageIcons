LuaUserData.RegisterType("Barotrauma.Sprite")
LuaUserData.RegisterType("Barotrauma.VisualSlot")

local cache = {}


function StorageIcons.resetCache()
    cache = {}
end

local function inWhitelist(identifier)
    for k in pairs(StorageIcons.Config["whitelistItems"]) do
        if identifier == k then
            return true
        end
    end
    return false
end


-- called when any item is moved into an inventory, does not account for some cases
Hook.Add("inventoryPutItem", "moveItem", function(inventory, item, characterUser, index, removeItemBool)
    local targetInventory = inventory.Owner
    if inWhitelist(targetInventory.Prefab.Identifier) and cache[targetInventory.ID] then
        cache[targetInventory.ID]["update"] = true
    elseif inWhitelist(item.Prefab.Identifier) and cache[item.ID] then
        -- scale may need to be updated due to some inventories having different scale
        cache[item.ID]["update"] = true
    end
end)


-- if an item is not placed into a new inventory (e.g. dropped on the ground) or in certain cases such as a fabricator pulling items from storage,
-- inventoryPutItem is not called, so this is used to update inventories items are taken from instead
-- RemoveItem(item)
Hook.Patch("Barotrauma.Inventory", "RemoveItem", function(instance, ptable)
    local inventory = ptable["item"].ParentInventory
    if not inventory then return end
    local item = inventory.Owner
    if item then
        if inWhitelist(item.Prefab.Identifier) and cache[item.ID] then
            cache[item.ID]["update"] = true
        end
    end
end, Hook.HookMethodType.Before)


-- firing weapons needs their magazine inventory updated, might be a better way to do this
-- public override bool Use(float deltaTime, Character character = null)
Hook.Patch("Barotrauma.Items.Components.RangedWeapon", "Use", function(instance, ptable)
    local character = ptable["character"]
    for item in character.heldItems do
        if item.OwnInventory then
            if cache[item.ID] then
                cache[item.ID]["update"] = true
            end
            local itemList = item.OwnInventory.FindAllItems()
            if itemList then
                for subItem in item.OwnInventory.FindAllItems() do
                    if inWhitelist(subItem.Prefab.Identifier) then
                        if cache[subItem.ID] then
                            cache[subItem.ID]["update"] = true
                        end
                    end
                end
            end
        end
    end
end)

local function drawItems(spriteBatch, rect, cached)
    local prefabs = cached.prefabs
    local rectCenter = rect.Center.ToVector2()

    -- If there's only one, draw it max size
    if #prefabs == 1 then
        local sprite = cached.drawInfo[prefabs[1]].sprite
        local color = cached.drawInfo[prefabs[1]].color
        local scale = cached.drawInfo[prefabs[1]].scale * StorageIcons.Config["iconScale"]
        local rotation = 0
        sprite.Draw(spriteBatch, rectCenter, color, rotation, scale)
        return
    end
    -- Otherwise, draw the four items in a 2x2 grid
    local offsetX = rect.Width / 4
    local offsetY = rect.Height / 4
    local positions = {
        -- items go ltr, top to bottom (sorry users who speak different languages...)
        Vector2.Add(rectCenter, Vector2(-offsetX, -offsetY)),
        Vector2.Add(rectCenter, Vector2(offsetX, -offsetY)),
        Vector2.Add(rectCenter, Vector2(-offsetX, offsetY)),
        Vector2.Add(rectCenter, Vector2(offsetX, offsetY)),
    }

    for i, prefab in ipairs(prefabs) do
        local itemPos = positions[i]
        local sprite = cached.drawInfo[prefab].sprite
        local color = cached.drawInfo[prefab].color
        local scale = cached.drawInfo[prefab].scale / 2
        local rotation = 0
        sprite.Draw(spriteBatch, itemPos, color, rotation, scale)
    end
end


Hook.Patch("Barotrauma.Inventory", "DrawSlot", function(instance, ptable)
    if not ptable["drawItem"] then return end
    local item = ptable["item"]

    if not item then return end
    if not item.OwnInventory then return end
    if not inWhitelist(item.Prefab.Identifier) then return end

    local itemCache = cache[item.ID]
    local spriteBatch = ptable["spriteBatch"]
    local rect = ptable["slot"].Rect

    if itemCache then
        if not itemCache["update"] then
            drawItems(spriteBatch, rect, itemCache)
            return
        end
    end
    if item.OwnInventory.IsEmpty() then return end

    local itemList = item.OwnInventory.FindAllItems()

    local itemCounts = {}
    local prefabs = {}
    local drawInfo = {}

    -- Determine which item is the most abundant and set sprite and color accordingly
    for v in itemList do
        local prefab = v.Prefab
        if itemCounts[prefab] then
            itemCounts[prefab] = itemCounts[prefab] + 1
        else
            itemCounts[prefab] = 1
            table.insert(prefabs, prefab)
        end

        if not drawInfo[prefab] then
            drawInfo[prefab] = {}
            -- noticed a modded item didn't have an InventoryIcon, idk if it's supposed to be optional
            local sprite = prefab.InventoryIcon or prefab.Sprite
            drawInfo[prefab].sprite = sprite
            drawInfo[prefab].color = v.GetSpriteColor()
            drawInfo[prefab].scale = math.min(2.0, (rect.Width - 10) / sprite.size.X, (rect.Height - 10) / sprite.size.Y)
        end
    end
    -- Pick (up to) the four most abundant items
    table.sort(prefabs, function(a, b) return itemCounts[a] > itemCounts[b] end)
    local abundant = table.pack(table.unpack(prefabs, 1, math.min(4, #prefabs)))

    -- store draw arguments to be used instead of recalculating if the inventory was not uppdated
    cache[item.ID] = {}
    cache[item.ID]["prefabs"] = abundant
    cache[item.ID]["drawInfo"] = drawInfo
    cache[item.ID]["update"] = false
    drawItems(spriteBatch, rect, cache[item.ID])
end, Hook.HookMethodType.After)


Hook.Add("roundStart", "clearCacheStart", function() StorageIcons.resetCache() end)
Hook.Add("roundEnd", "clearCacheEnd", function() StorageIcons.resetCache() end)
