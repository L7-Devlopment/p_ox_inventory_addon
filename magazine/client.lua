local Config = require 'magazine.config'
local isReloading = false

local function assertMetadata(metadata)
    if metadata and type(metadata) ~= 'table' then
        metadata = metadata and { type = metadata or nil }
    end

    return metadata
end
 
function ReturnFirstOrderedItem(itemName, metadata, strict)
    local inventory = exports.ox_inventory:GetPlayerItems()
    
    local item = exports.ox_inventory:Items(itemName)
    if item then
        return exports.ox_inventory:GetSlotIdWithItem(itemName, {}, strict)
    else
        item = exports.ox_inventory:Items('Magazine')
        if not item then return end

        local matchedItems = {}
        metadata = assertMetadata(metadata)
        local tablematch = strict and lib.table.matches or lib.table.contains
        
        for _, slotData in pairs(inventory) do
            if slotData and slotData.name == item.name and slotData.metadata.ammo > 0 and slotData.metadata.magType == itemName and (not metadata or tablematch(slotData.metadata, metadata)) then
                table.insert(matchedItems, slotData)
            end
        end
        
        if #matchedItems == 0 then return end

        table.sort(matchedItems, function(a, b)
            return (a.metadata.ammo or 0) > (b.metadata.ammo or 0)
        end)

        return matchedItems[1].slot
    end
end
exports('ReturnFirstOrderedItem', ReturnFirstOrderedItem)

local function packMagazine(currentMag)
    exports.ox_inventory:useItem({
        name = currentMag.item.name,
        slot = currentMag.item.slot,
        metadata = currentMag.item.metadata,
    }, function(resp)
        if not resp then return end
        isReloading = true
        local bulletsAddedToMag = 0

        CreateThread(function()
            while isReloading do
                local animDict = "cover@weapon@reloads@pistol@pistol"
                local animName = "reload_low_left_long"
                if not isReloading then break end

                -- Stop if magazine is full
                if resp.metadata.ammo + bulletsAddedToMag >= resp.metadata.magSize then
                    isReloading = false
                    break
                end

                -- Stop if no bullets left in inventory
                local slotId = exports.ox_inventory:GetSlotIdWithItem(resp.metadata.ammoType, {}, false)
                if not slotId then
                    isReloading = false
                    break
                end

                -- Progress bar for adding one bullet
                if lib.progressCircle({
                    duration = Config.MagazineReloadTime,
                    position = 'bottom',
                    label = 'pack_magazine',
                    useWhileDead = false,
                    canCancel = true,
                    disable = {
                        move = false,
                        car = true,
                        combat = true,
                        mouse = false,
                    },
                    anim = {
                        clip = animName,
                        dict= animDict,
                        flag = 49
                    }
                })
                then
                    bulletsAddedToMag = bulletsAddedToMag + 1
                    resp.metadata.durability = math.max(1, math.floor((resp.metadata.ammo + bulletsAddedToMag) / resp.metadata.magSize * 100))
                else
                    isReloading = false
                end
            end

            -- Update magazine with whatever bullets were added
            local result = lib.callback.await('p_ox_inventory_addon:updateMagazine', false, 'loadMagazine', bulletsAddedToMag, resp.slot, nil)
            isReloading = false
        end)
    end)
end


local function useMagazine(data, context)
    local playerPed = cache.ped
    local weapon = exports.ox_inventory:getCurrentWeapon()

    if not weapon then return end
    if weapon.ammo ~= context.metadata.magType then 
        lib.notify({ id = 'no_magazine', type = 'error', description = 'no_magazine_found' }) 
        return 
    end
    if context.metadata.ammo < 1 then 
        lib.notify({ id = 'no_magazine', type = 'error', description = 'no_magazine_found' }) 
        return 
    end
    if isReloading then return end

    isReloading = true

    exports.ox_inventory:useItem(data, function(resp)
        if not resp then 
            isReloading = false 
            return 
        end

        local result = lib.callback.await(
            'p_ox_inventory_addon:updateMagazine',
            false,
            'load',
            resp.metadata.ammo,
            context.slot,
            weapon.metadata or nil
        )

        if not result or not result.success then
            local reason = result and result.reason or 'Server timeout or no response'
            lib.notify({ id = 'reload_failed', type = 'error', description = 'Failed to reload: ' .. reason })
            isReloading = false
            return
        end

        local clipSize = GetMaxAmmoInClip(playerPed, weapon.hash, true)
        local roundsToSet = resp.metadata.ammo or 0
        if clipSize and roundsToSet > clipSize then
            roundsToSet = clipSize
        end

        SetAmmoInClip(playerPed, weapon.hash, 0)
        SetPedAmmo(playerPed, weapon.hash, roundsToSet)
        MakePedReload(playerPed)

        weapon.metadata.ammo = resp.metadata.ammo
        weapon.metadata.hasMagazine = true
        isReloading = false
    end)
end
RegisterNetEvent('p_ox_inventory_addon:packMagazine', function(magItem)
    currentMag = {
        prop = 0,
        item = magItem,
        slot = magItem.slot,
        metadata = lib.table.clone(magItem.metadata),
    }
    packMagazine(currentMag)
end)

lib.addKeybind({
    name = 'reloadweapon_addon',
    description = 'reload_weapon_addon',
    defaultKey = 'r',
    onPressed = function(self)
        local currentWeapon = exports.ox_inventory:getCurrentWeapon(true)
        if not currentWeapon then return end
        if currentWeapon.ammo then
            if currentWeapon.metadata.durability > 0 then
                local slotId = ReturnFirstOrderedItem(currentWeapon.ammo, { magType = currentWeapon.metadata.magType }, false)

                if slotId then
                    exports.ox_inventory:useSlot(slotId)
                else
                    lib.notify({ id = 'no_magazine', type = 'error', description = 'no_magazine_found' })
                end
            else
                lib.notify({ id = 'no_durability', type = 'error', description = 'no_durability' })
            end
            return
        end
    end
})

exports('packMagazine', packMagazine)
exports('useMagazine', useMagazine)
