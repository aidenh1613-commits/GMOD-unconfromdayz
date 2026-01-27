print("cl.uncon.lua loaded")

local blurActive = false
local fadeCancelled = false
local blurMaterial = Material("pp/blurscreen")

net.Receive("UnconDayz_BlurOn", function()
    blurActive = true
    fadeCancelled = false
    surface.PlaySound("uncon/dayz_bodyfall.wav")
end)

net.Receive("UnconDayz_BlurOff", function()
    blurActive = false
    fadeCancelled = true
end)

hook.Add("HUDPaint", "UnconDayz_DrawBlur", function()
    if not blurActive then return end
    surface.SetDrawColor(255, 255, 255)
    surface.SetMaterial(blurMaterial)
    for i = 1, 3 do
        blurMaterial:SetFloat("$blur", i * 1.5)
        blurMaterial:Recompute()
        render.UpdateScreenEffectTexture()
        surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
    end
end)

net.Receive("UnconDayz_Fade", function()
    local action = net.ReadString()
    local duration = net.ReadFloat() or 2
    local ply = LocalPlayer()
    fadeCancelled = false

    local hold = nil
    if net.BytesLeft() >= 4 then hold = net.ReadFloat() end
    hold = hold or 0

    if action == "out" then
        ply:ScreenFade(SCREENFADE.OUT, Color(0, 0, 0), math.max(duration, 0.01), math.max(hold, 0))
    elseif action == "in" then
        ply:ScreenFade(SCREENFADE.IN, Color(0, 0, 0), math.max(duration, 0.01), math.max(hold, 0))
    end
end)

net.Receive("UnconDayz_PlayBodyfall", function()
    surface.PlaySound("uncon/dayz_bodyfall.wav")
end)

