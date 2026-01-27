resource.AddFile("sound/uncon/dayz_bodyfall.wav")

util.AddNetworkString("UnconDayz_Fade")
util.AddNetworkString("UnconDayz_BlurOn")
util.AddNetworkString("UnconDayz_BlurOff")
util.AddNetworkString("UnconDayz_PlayBodyfall")

print("[UnconDayz] File loaded")

local DAMAGE_THRESHOLD = 20
local REVIVE_HEALTH = 25
local COOLDOWN_TIME = 5
local reviveTimers = {}

-- Timing config (seconds)
local TIME_TO_FADE_IN = 17
local DURATION_FADE_IN = 2
local DELAY_AFTER_FADE_IN = 0
local DURATION_FADE_OUT = 2
local WAKE_DELAY_AFTER_FADE_OUT = 9


local function SafeRemoveRagdoll(rag)
    if not IsValid(rag) then return end
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local bp = rag:GetPhysicsObjectNum(i)
        if IsValid(bp) then
            bp:Wake()
            bp:EnableMotion(true)
        end
    end
    rag:Remove()
end

hook.Add("EntityTakeDamage", "UnconDayTrigger", function(ent, dmginfo)
    if not ent:IsPlayer() then return end
    if not ent:Alive() then return end
    if ent._unconscious then return end
    if ent._unconscious_cooldown then return end
    if ent:Health() > UnconDayz_HPThreshold then return end

    print("[UnconDayz] Triggering unconsciousness for", ent:Nick())

    timer.Simple(math.Rand(0.5, 1.5), function()
        if not IsValid(ent) or not ent:Alive() then return end
        if ent._unconscious or ent._unconscious_cooldown then return end
        if ent:Health() > UnconDayz_HPThreshold then return end

        -- logic begins
        ent._unconscious = true
        ent:Freeze(true)
        ent:SetMoveType(MOVETYPE_NONE)
        ent._uncon_original_pos = ent:GetPos()
        ent:SetNoDraw(true)
        ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

        local rag = ents.Create("prop_ragdoll")
        if not IsValid(rag) then return end
        rag:SetModel(ent:GetModel())
        rag:SetPos(ent:GetPos())
        rag:SetAngles(ent:GetAngles())
        rag:Spawn()
        rag:EmitSound("uncon/dayz_bodyfall.wav", 180, 100, 1, CHAN_STATIC)
        net.Start("UnconDayz_PlayBodyfall") net.Send(ent)

        rag:SetNotSolid(true)
        timer.Simple(0.1, function() if IsValid(rag) then rag:SetNotSolid(false) end end)
        rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

        local pv = ent:GetVelocity()
        local mainPhys = rag:GetPhysicsObject()
        if IsValid(mainPhys) then
            mainPhys:SetMass(math.max(mainPhys:GetMass(), 20))
            mainPhys:Wake()
            mainPhys:SetVelocity(pv)
        end
        for i = 0, rag:GetPhysicsObjectCount() - 1 do
            local bonePhys = rag:GetPhysicsObjectNum(i)
            if IsValid(bonePhys) then
                bonePhys:Wake()
                bonePhys:SetMass(math.max(bonePhys:GetMass(), 5))
                bonePhys:SetVelocity(pv * 0.9)
                bonePhys:AddAngleVelocity(VectorRand() * 20)
            end
        end
        timer.Simple(0.6, function() if IsValid(rag) then rag:SetCollisionGroup(COLLISION_GROUP_WEAPON) end end)

        rag:SetNWEntity("UnconOwner", ent)
        rag.UnconOwner = ent
        ent:SetViewEntity(rag)

        net.Start("UnconDayz_Fade") net.WriteString("out") net.WriteFloat(0.01) net.WriteFloat(TIME_TO_FADE_IN) net.Send(ent)
        net.Start("UnconDayz_BlurOn") net.Send(ent)

        if reviveTimers[ent] then
            timer.Remove(reviveTimers[ent])
            reviveTimers[ent] = nil
        end

        timer.Simple(TIME_TO_FADE_IN, function()
            if IsValid(ent) and ent._unconscious then
                net.Start("UnconDayz_Fade") net.WriteString("in") net.WriteFloat(DURATION_FADE_IN) net.Send(ent)
            end
        end)

        local fadeOutStart = TIME_TO_FADE_IN + DURATION_FADE_IN + DELAY_AFTER_FADE_IN
        timer.Simple(fadeOutStart, function()
            if IsValid(ent) and ent._unconscious then
                net.Start("UnconDayz_Fade") net.WriteString("out") net.WriteFloat(DURATION_FADE_OUT) net.WriteFloat(WAKE_DELAY_AFTER_FADE_OUT) net.Send(ent)
            end
        end)

        local totalBeforeWake = fadeOutStart + DURATION_FADE_OUT + WAKE_DELAY_AFTER_FADE_OUT
        local timerID = "UnconDayz_Revive_" .. ent:SteamID()
        reviveTimers[ent] = timerID

        timer.Create(timerID, totalBeforeWake, 1, function()
            reviveTimers[ent] = nil
            if not IsValid(ent) or not ent:Alive() then
                print("[UnconDayz] Revive aborted — player is dead or invalid.")
                for _, r in ipairs(ents.FindByClass("prop_ragdoll")) do
                    if r.UnconOwner == ent then SafeRemoveRagdoll(r) end
                end
                return
            end

            print("[UnconDayz] Reviving", ent:Nick())
            ent:SetViewEntity(nil)
            timer.Simple(0.1, function() if IsValid(ent) then net.Start("UnconDayz_BlurOff") net.Send(ent) end end)

            local revivePos = nil
            if IsValid(rag) then
                local start = rag:GetPos() + Vector(0,0,8)
                local tr = util.TraceHull({
                    start = start,
                    endpos = start - Vector(0,0,200),
                    mask = MASK_PLAYERSOLID,
                    mins = Vector(-16, -16, 0),
                    maxs = Vector(16, 16, 72),
                    filter = {rag, ent}
                })
                revivePos = tr.Hit and tr.HitPos and (tr.HitPos + tr.HitNormal * 16) or (rag:GetPos() + Vector(0,0,16))
            end
            revivePos = revivePos or ent._uncon_original_pos or ent:GetPos()
            if not util.IsInWorld(revivePos) then revivePos = ent._uncon_original_pos or ent:GetPos() end

            local safeTr = util.TraceHull({
                start = revivePos,
                endpos = revivePos,
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, 72),
                mask = MASK_PLAYERSOLID,
                filter = ent
            })
            local attempts = 0
            while safeTr.StartSolid and attempts < 6 do
                revivePos = revivePos + Vector(0,0,24)
                safeTr = util.TraceHull({
                    start = revivePos,
                    endpos = revivePos,
                    mins = Vector(-16, -16, 0),
                    maxs = Vector(16, 16, 72),
                    mask = MASK_PLAYERSOLID,
                    filter = ent
                })
                attempts = attempts + 1
            end

            ent:SetPos(revivePos)
            if ent.ResetLighting then ent:ResetLighting() end
            if ent.DrawShadow then ent:DrawShadow(true) end
            if ent.InvalidateBoneCache then ent:InvalidateBoneCache(); ent:SetupBones() end

            if IsValid(rag) then
                if ent:GetModel() ~= rag:GetModel() then ent:SetModel(rag:GetModel()) end
                SafeRemoveRagdoll(rag)
            end

            ent:SetNoDraw(false)
            ent:SetCollisionGroup(COLLISION_GROUP_PLAYER)
            ent:Freeze(false)
            ent:SetMoveType(MOVETYPE_WALK)
            ent:SetHealth(REVIVE_HEALTH)
            ent._unconscious = false
            ent._uncon_original_pos = nil

            ent._unconscious_cooldown = true
            timer.Simple(COOLDOWN_TIME, function()
                if IsValid(ent) then
                    ent._unconscious_cooldown = false
                    print("[UnconDayz] Cooldown ended for", ent:Nick())
                end
            end)

            ent:ChatPrint("[UnconDayz] You regained consciousness.")
        end)
    end)
end)


-- Redirect damage from ragdoll to owner
hook.Add("EntityTakeDamage", "UnconDayz_RagdollDamageRedirect", function(target, dmginfo)
    if not IsValid(target) then return end
    if target:GetClass() ~= "prop_ragdoll" then return end
    local owner = target.UnconOwner
    if IsValid(owner) and owner._unconscious then
        if dmginfo:IsDamageType(DMG_CRUSH) or dmginfo:IsFallDamage() then return end
        owner:TakeDamageInfo(dmginfo)
    end
end)

hook.Add("PlayerDeath", "UnconDayz_CleanupAndRespawn", function(ply)
    if not ply._unconscious then return end

    print("[UnconDayz] Player died while unconscious:", ply:Nick())

    ply._unconscious = false
    ply._unconscious_cooldown = false
    ply._uncon_original_pos = nil

    ply:SetViewEntity(nil)

    net.Start("UnconDayz_BlurOff")
    net.Send(ply)

    for _, rag in pairs(ents.FindByClass("prop_ragdoll")) do
        if rag.UnconOwner == ply then
            SafeRemoveRagdoll(rag)
        end
    end

    local timerID = reviveTimers[ply]
    if timerID then
        timer.Remove(timerID)
        reviveTimers[ply] = nil
    end

    timer.Simple(1, function()
        if IsValid(ply) and not ply:Alive() then
            ply:Spawn()
            print("[UnconDayz] Forced respawn for", ply:Nick())
        end
    end)
end)

hook.Add("PlayerDisconnected", "UnconDayz_CleanupOnDisconnect", function(ply)
    if not ply._unconscious then return end

    print("[UnconDayz] Player disconnected while unconscious:", ply:Nick())

    for _, rag in pairs(ents.FindByClass("prop_ragdoll")) do
        if rag.UnconOwner == ply then
            SafeRemoveRagdoll(rag)
        end
    end

    local timerID = reviveTimers[ply]
    if timerID then
        timer.Remove(timerID)
        reviveTimers[ply] = nil
    end
end)


hook.Add("PlayerDisconnected", "UnconDayz_CleanupOnDisconnect", function(ply)
    if not ply._unconscious then return end

    print("[UnconDayz] Player disconnected while unconscious:", ply:Nick())

    for _, rag in pairs(ents.FindByClass("prop_ragdoll")) do
        if rag.UnconOwner == ply then
            SafeRemoveRagdoll(rag)
        end
    end

    local timerID = reviveTimers[ply]
    if timerID then
        timer.Remove(timerID)
        reviveTimers[ply] = nil
    end
end)

local reviveTimers = reviveTimers or {} -- preserve existing table if present

local function SafeRemoveRagdoll(rag)
    if not IsValid(rag) then return end
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local bp = rag:GetPhysicsObjectNum(i)
        if IsValid(bp) then
            bp:Wake()
            bp:EnableMotion(true)
        end
    end
    rag:Remove()
end

UnconDayz_HPThreshold = 20 -- default HP required to trigger unconsciousness

-- Core unconscious routine (NtS: call this directly to force unconsciousness)
function UnconDayz_DoUnconscious(ent)
    if not IsValid(ent) or not ent:IsPlayer() then return false end
    if not ent:Alive() then return false end
    if ent._unconscious then return false end
    if ent._unconscious_cooldown then return false end

    ent._unconscious = true
    ent:Freeze(true)
    ent:SetMoveType(MOVETYPE_NONE)

    local originalPos = ent:GetPos()
    ent._uncon_original_pos = originalPos

    ent:SetNoDraw(true)
    ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then
        -- cleanup and bail
        ent._unconscious = false
        ent:SetNoDraw(false)
        ent:SetCollisionGroup(COLLISION_GROUP_PLAYER)
        ent:Freeze(false)
        ent:SetMoveType(MOVETYPE_WALK)
        return false
    end

    rag:SetModel(ent:GetModel())
    rag:SetPos(originalPos)
    rag:SetAngles(ent:GetAngles())
    rag:Spawn()

    rag:EmitSound("uncon/dayz_bodyfall.wav", 180, 100, 1, CHAN_STATIC)
    net.Start("UnconDayz_PlayBodyfall") net.Send(ent)

    rag:SetNotSolid(true)
    timer.Simple(0.1, function() if IsValid(rag) then rag:SetNotSolid(false) end end)

    rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local pv = ent:GetVelocity()
    local mainPhys = rag:GetPhysicsObject()
    if IsValid(mainPhys) then
        mainPhys:SetMass(math.max(mainPhys:GetMass(), 20))
        mainPhys:Wake()
        mainPhys:SetVelocity(pv)
    end

    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local bonePhys = rag:GetPhysicsObjectNum(i)
        if IsValid(bonePhys) then
            bonePhys:Wake()
            bonePhys:SetMass(math.max(bonePhys:GetMass(), 5))
            bonePhys:SetVelocity(pv * 0.9)
            bonePhys:AddAngleVelocity(VectorRand() * 20)
        end
    end

    timer.Simple(0.6, function() if IsValid(rag) then rag:SetCollisionGroup(COLLISION_GROUP_WEAPON) end end)

    rag:SetNWEntity("UnconOwner", ent)
    rag.UnconOwner = ent
    ent:SetViewEntity(rag)

    net.Start("UnconDayz_Fade") net.WriteString("out") net.WriteFloat(0.01) net.WriteFloat(TIME_TO_FADE_IN) net.Send(ent)
    net.Start("UnconDayz_BlurOn") net.Send(ent)

    -- clear any existing revive timer
    if reviveTimers[ent] then
        timer.Remove(reviveTimers[ent])
        reviveTimers[ent] = nil
    end

    local fadeOutStart = TIME_TO_FADE_IN + DURATION_FADE_IN + DELAY_AFTER_FADE_IN
    timer.Simple(TIME_TO_FADE_IN, function() if IsValid(ent) and ent._unconscious then net.Start("UnconDayz_Fade") net.WriteString("in") net.WriteFloat(DURATION_FADE_IN) net.Send(ent) end end)
    timer.Simple(fadeOutStart, function() if IsValid(ent) and ent._unconscious then net.Start("UnconDayz_Fade") net.WriteString("out") net.WriteFloat(DURATION_FADE_OUT) net.WriteFloat(WAKE_DELAY_AFTER_FADE_OUT) net.Send(ent) end end)

    local totalBeforeWake = fadeOutStart + DURATION_FADE_OUT + WAKE_DELAY_AFTER_FADE_OUT
    local timerID = "UnconDayz_Revive_" .. ent:SteamID()
    reviveTimers[ent] = timerID

    timer.Create(timerID, totalBeforeWake, 1, function()
        reviveTimers[ent] = nil
        if not IsValid(ent) or not ent:Alive() then
            for _, r in ipairs(ents.FindByClass("prop_ragdoll")) do
                if r.UnconOwner == ent then SafeRemoveRagdoll(r) end
            end
            return
        end

        ent:SetViewEntity(nil)
        timer.Simple(0.1, function() if IsValid(ent) then net.Start("UnconDayz_BlurOff") net.Send(ent) end end)

        local revivePos = nil
        if IsValid(rag) then
            local start = rag:GetPos() + Vector(0,0,8)
            local tr = util.TraceHull({
                start = start,
                endpos = start - Vector(0,0,200),
                mask = MASK_PLAYERSOLID,
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, 72),
                filter = {rag, ent}
            })
            if tr.Hit and tr.HitPos then
                revivePos = tr.HitPos + tr.HitNormal * 16
            else
                revivePos = rag:GetPos() + Vector(0,0,16)
            end
        end
        revivePos = revivePos or ent._uncon_original_pos or ent:GetPos()

        if not util.IsInWorld(revivePos) then
            revivePos = ent._uncon_original_pos or ent:GetPos()
        end

        local safeTr = util.TraceHull({
            start = revivePos,
            endpos = revivePos,
            mins = Vector(-16, -16, 0),
            maxs = Vector(16, 16, 72),
            mask = MASK_PLAYERSOLID,
            filter = ent
        })
        local attempts = 0
        while safeTr.StartSolid and attempts < 6 do
            revivePos = revivePos + Vector(0,0,24)
            safeTr = util.TraceHull({
                start = revivePos,
                endpos = revivePos,
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, 72),
                mask = MASK_PLAYERSOLID,
                filter = ent
            })
            attempts = attempts + 1
        end

        ent:SetPos(revivePos)

        if ent.ResetLighting then ent:ResetLighting() end
        if ent.DrawShadow then ent:DrawShadow(true) end
        if ent.InvalidateBoneCache then ent:InvalidateBoneCache(); ent:SetupBones() end

        if IsValid(rag) then
            if ent:GetModel() ~= rag:GetModel() then ent:SetModel(rag:GetModel()) end
            SafeRemoveRagdoll(rag)
        end

        ent:SetNoDraw(false)
        ent:SetCollisionGroup(COLLISION_GROUP_PLAYER)
        ent:Freeze(false)
        ent:SetMoveType(MOVETYPE_WALK)
        ent:SetHealth(REVIVE_HEALTH)
        ent._unconscious = false
        ent._uncon_original_pos = nil

        ent._unconscious_cooldown = true
        timer.Simple(COOLDOWN_TIME, function() if IsValid(ent) then ent._unconscious_cooldown = false end end)

        ent:ChatPrint("[UnconDayz] You regained consciousness.")
    end)

    return true
end

concommand.Add("uncon_force", function(ply, cmd, args)
    local isConsole = (not IsValid(ply))
    if not isConsole and IsValid(ply) and ply:IsPlayer() and not game.SinglePlayer() then
        if not ply:IsAdmin() then ply:ChatPrint("You must be an admin to use uncon_force.") return end
    end

    if not args[1] then
        if isConsole then print("[UnconDayz] Usage: uncon_force <playername>") else ply:ChatPrint("Usage: uncon_force <playername>") end
        return
    end

    local needle = string.lower(args[1])
    local target = nil
    for _, v in ipairs(player.GetAll()) do
        if string.find(string.lower(v:Nick()), needle, 1, true) then target = v break end
    end

    if not IsValid(target) then
        if isConsole then print("[UnconDayz] No player found matching: " .. args[1]) else ply:ChatPrint("No player found matching: " .. args[1]) end
        return
    end

    local ok = UnconDayz_DoUnconscious(target)
    if ok then
       if isConsole then print("[UnconDayz] Forced unconsciousness for " .. target:Nick()) end
    else
        if isConsole then print("[UnconDayz] Could not force unconsciousness for " .. target:Nick()) end
    end
end)

concommand.Add("uncon_sethp", function(ply, cmd, args)
    local isConsole = not IsValid(ply)
    if not isConsole and not ply:IsAdmin() then
        ply:ChatPrint("You must be an admin to use uncon_sethp.")
        return
    end

    local newVal = tonumber(args[1])
    if not newVal or newVal < 1 or newVal > 1000 then
        if isConsole then
            print("[UnconDayz] Usage: uncon_sethp <value between 1 and 1000>")
        else
            ply:ChatPrint("Usage: uncon_sethp <value between 1 and 1000>")
        end
        return
    end

    UnconDayz_HPThreshold = newVal
    local msg = "[UnconDayz] Unconsciousness HP threshold set to " .. newVal
    if isConsole then print(msg) else ply:ChatPrint(msg) end
end)


hook.Add("PlayerSay", "UnconDayz_FaintCommand_Debug", function(ply, text)
    if string.lower(text) ~= "!faint" then return end
    if not IsValid(ply) or not ply:Alive() then return "" end
    if ply._unconscious then
        ply:ChatPrint("[UnconDayz] You're already unconscious.")
        return ""
    end
    if ply._unconscious_cooldown then
        ply:ChatPrint("[UnconDayz] You are on cooldown.")
        return ""
    end

    local faintDuration = 30 -- seconds

    -- Play gasp for nearby players
    local soundPath = "uncon/gasp.wav"
    sound.Play(soundPath, ply:GetPos(), 100, 100, 1)

    local ok, resOrErr = pcall(function() return UnconDayz_DoUnconscious(ply, faintDuration) end)
    if not ok then
        -- pcall failure (runtime error)
        print("[UnconDayz] Error calling UnconDayz_DoUnconscious(ply, duration):", resOrErr)
        ply:ChatPrint("[UnconDayz] Error: see server console for details.")
        return ""
    end

    if resOrErr then
        ply:ChatPrint("[UnconDayz] You have fainted for " .. tostring(faintDuration) .. "s.")
        print("[UnconDayz] !faint triggered for " .. ply:Nick() .. " (duration param accepted).")
        return ""
    end

    local ok2, resOrErr2 = pcall(function() return UnconDayz_DoUnconscious(ply) end)
    if not ok2 then
        print("[UnconDayz] Error calling UnconDayz_DoUnconscious(ply):", resOrErr2)
        ply:ChatPrint("[UnconDayz] Error: see server console for details.")
        return ""
    end

    if resOrErr2 then
        ply:ChatPrint("[UnconDayz] You fainted (fallback) — server-side may not support duration param.")
        print("[UnconDayz] !faint triggered for " .. ply:Nick() .. " (fallback, no duration).")
        return ""
    end

    -- final failure
    ply:ChatPrint("[UnconDayz] Could not force faint; function returned false. Check server console.")
    print("[UnconDayz] !faint failed for " .. ply:Nick() .. " — UnconDayz_DoUnconscious returned false.")
    return ""
end)

