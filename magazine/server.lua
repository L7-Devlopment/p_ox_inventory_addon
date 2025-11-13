local function updateMagazine(source, action, value, slot, specialAmmo)
	local inventory = exports.ox_inventory:GetInventory(source)
	if not inventory then return { success = false, reason = 'No inventory found' } end

    if action == 'load' then
        local weapon = exports.ox_inventory:GetCurrentWeapon(source)
        if not weapon or not weapon.metadata then return { success = false, reason = 'No weapon equipped or weapon has no metadata' } end
        local magazine = exports.ox_inventory:GetSlot(source, slot)
        if not magazine then return { success = false, reason = 'Magazine slot is empty' } end
        local ammo = magazine.metadata.label
        local currentWepAmmo = weapon.metadata.ammo or 0
        local newMagazineMetadata = {
            label    = magazine.metadata.label,
            magType  = magazine.metadata.magType,
            ammoType = magazine.metadata.ammoType,
            magSize  = magazine.metadata.magSize,
            model    = magazine.metadata.model,
            ammo     = currentWepAmmo,
            image    = magazine.metadata.image,
            durability = math.max(1, math.floor((currentWepAmmo / magazine.metadata.magSize) * 100))
        }
                                                         
        local itemKey = magazine.name
        local magType = magazine and magazine.metadata and magazine.metadata.magType
        local metadata = magType and { magType = magType } or nil

        if not exports.ox_inventory:RemoveItem(source, itemKey, 1, metadata, slot, false, false) then 
            return { success = false, reason = 'Failed to remove magazine from inventory' } 
        end

        if currentWepAmmo > 0 or weapon.metadata.hasMagazine then
            exports.ox_inventory:AddItem(source, itemKey, 1, newMagazineMetadata)
        end

        weapon.metadata.ammo = value
        weapon.metadata.hasMagazine = true
        weapon.metadata.magazineType = ammo
        --weapon.weight = Inventory.SlotWeight(item, weapon)
        exports.ox_inventory:SetMetadata(source, weapon.slot, weapon.metadata)
    elseif action == 'loadMagazine' then
        local magazine = exports.ox_inventory:GetSlot(source, slot)
        if not magazine then return { success = false, reason = 'Magazine slot is empty' } end
        --Server Check to validate that client didn't add more ammo than magSize
        local magCheck = magazine.metadata.ammo + value
        if magCheck > magazine.metadata.magSize then 
            return { success = false, reason = 'Magazine would exceed max capacity' } 
        end

        if not exports.ox_inventory:RemoveItem(source, magazine.metadata.ammoType, value) then 
            return { success = false, reason = 'Failed to remove ammo from inventory' } 
        end
        magazine.metadata.ammo = magCheck
        magazine.metadata.durability = math.max(1, math.floor((magCheck / magazine.metadata.magSize) * 100))
        exports.ox_inventory:SetMetadata(source, slot, magazine.metadata)
    else
        return { success = false, reason = 'Invalid action: ' .. tostring(action) }
    end

    return { success = true }
end

lib.callback.register('p_ox_inventory_addon:updateMagazine', updateMagazine)

RegisterNetEvent('p_ox_inventory_addon:updateMagazine', function(action, value, slot, specialAmmo)
	updateMagazine(source, action, value, slot, specialAmmo)
end)

exports.ox_inventory:registerHook('swapItems', function(payload)
    if type(payload.toSlot) == 'table' and payload.toSlot.name == 'magazine' then
        if type(payload.fromSlot) == 'table' and payload.fromSlot.name == payload.toSlot.metadata.ammoType then
            -- Trigger client-side packMagazine
            TriggerClientEvent('p_ox_inventory_addon:packMagazine', payload.source, payload.toSlot)
            
            -- Prevent normal swap
            return false
        end
    end
    return true
end)

exports.ox_inventory:registerHook('createItem', function(payload)
    if payload.item.magazine then
        payload.metadata.id = tostring(math.random(100000,999999)) .. tostring(GetGameTimer())
    end

    return payload.metadata
end)

