--[[
getgenv().Settings = {
    CopyButton = false,
}
]]

local CoreGui = game:GetService("CoreGui")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local COLORS = {
    IDLE = Color3.fromRGB(34, 214, 78),
    HOVER = Color3.fromRGB(42, 232, 90),
}
local COPY_COLORS = {
    IDLE = Color3.fromRGB(255, 154, 46),
    HOVER = Color3.fromRGB(255, 176, 84),
}
local TWEEN_SPEED = TweenInfo.new(0.045, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LastPrompt = { Id = nil, Type = nil }
local SETTINGS_DEFAULTS = {
    CopyButton = false,
}

local function getSettings()
    local resolved = table.clone(SETTINGS_DEFAULTS)
    local ok, envSettings = pcall(function()
        if type(getgenv) ~= "function" then return false end
        local env = getgenv()
        if type(env) ~= "table" then return false end
        local settings = env.Settings
        if type(settings) ~= "table" then return false end
        return settings
    end)
    if not ok or envSettings == false then
        return resolved
    end
    for key, defaultValue in pairs(SETTINGS_DEFAULTS) do
        if type(envSettings[key]) == "boolean" then
            resolved[key] = envSettings[key]
        else
            resolved[key] = defaultValue
        end
    end
    return resolved
end

local function isSettingEnabled(name)
    return getSettings()[name] == true
end

local RuntimeState = nil
pcall(function()
    local env = type(getgenv) == "function" and getgenv() or nil
    if type(env) == "table" then
        env.__FreeGamepassRuntime = env.__FreeGamepassRuntime or { runId = 0 }
        env.__FreeGamepassRuntime.runId = env.__FreeGamepassRuntime.runId + 1
        RuntimeState = env.__FreeGamepassRuntime
    end
end)

local CURRENT_RUN_ID = RuntimeState and RuntimeState.runId or os.clock()

local function toggleRobloxMenu()
    pcall(function()
        GuiService:SetMenuIsOpen(true)
        GuiService:SetMenuIsOpen(false)
    end)
end

local function trySet(obj, prop, value)
    pcall(function()
        obj[prop] = value
    end)
end

local function tweenColor(target, color)
    if not target or not target.Parent then return end

    local props = {}
    if target:IsA("GuiObject") then
        props.BackgroundColor3 = color
    end
    if target:IsA("ImageButton") or target:IsA("ImageLabel") then
        props.ImageColor3 = color
    end
    if next(props) then
        TweenService:Create(target, TWEEN_SPEED, props):Play()
    end
end

local function applyVisualState(root, color)
    tweenColor(root, color)
    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("ImageLabel") or desc:IsA("ImageButton") or desc:IsA("Frame") then
            tweenColor(desc, color)
        end
    end
end

local function capturePrompt(player, id, promptType)
    if player == LocalPlayer then
        LastPrompt.Id = id
        LastPrompt.Type = promptType
    end
end

MarketplaceService.PromptGamePassPurchaseRequested:Connect(function(player, id)
    capturePrompt(player, id, "GamePass")
end)

MarketplaceService.PromptProductPurchaseRequested:Connect(function(player, id)
    capturePrompt(player, id, "Product")
end)

local function finishPurchase(id)
    if LastPrompt.Type == "GamePass" then
        local success = pcall(function()
            MarketplaceService:SignalPromptGamePassPurchaseFinished(LocalPlayer.UserId, id, true)
        end)
        if not success then
            pcall(function()
                MarketplaceService:PromptGamePassPurchaseFinished(LocalPlayer, id)
            end)
        end
        return
    end

    local success = pcall(function()
        MarketplaceService:SignalPromptProductPurchaseFinished(LocalPlayer.UserId, id, true)
    end)
    if not success then
        pcall(function()
            MarketplaceService:PromptProductPurchaseFinished(LocalPlayer, id)
        end)
    end
end

local function buildPurchaseOperation(id)
    if LastPrompt.Type == "GamePass" then
        return string.format(
            "local MarketplaceService = game:GetService(\"MarketplaceService\")\n\nMarketplaceService:SignalPromptGamePassPurchaseFinished(%d, %d, true)",
            LocalPlayer.UserId,
            id
        )
    end
    return string.format(
        "local MarketplaceService = game:GetService(\"MarketplaceService\")\n\nMarketplaceService:SignalPromptProductPurchaseFinished(%d, %d, true)",
        LocalPlayer.UserId,
        id
    )
end

local function positionCopyButton(freeBtn, copyBtn, parent)
    if not freeBtn then return end
    if parent:FindFirstChildOfClass("UIListLayout") then
        copyBtn.LayoutOrder = (freeBtn.LayoutOrder or 0) + 1
        return
    end
    copyBtn.Position = freeBtn.Position + UDim2.fromOffset(0, 42)
end

local function decorateButton(btn, text, zIndex, palette)
    local colors = palette or COLORS
    btn.Visible = true
    btn.Active = true
    btn.Selectable = true
    btn.AutoButtonColor = false
    btn.ZIndex = zIndex
    btn.BackgroundColor3 = colors.IDLE
    btn.BackgroundTransparency = 0.1
    trySet(btn, "Interactable", true)
    if btn:IsA("ImageButton") then
        btn.ImageColor3 = colors.IDLE
    end

    for _, desc in ipairs(btn:GetDescendants()) do
        if desc:IsA("LocalScript") or desc:IsA("Script") or desc:IsA("ModuleScript") then
            desc:Destroy()
        elseif desc:IsA("GuiObject") then
            desc.ZIndex = math.max(desc.ZIndex, btn.ZIndex)
            desc.Active = true
            trySet(desc, "Interactable", true)
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                desc.Text = text
                desc.TextTransparency = 0
            end
        end
    end
end

local function wireHover(btn, palette)
    local colors = palette or COLORS
    btn.MouseEnter:Connect(function()
        applyVisualState(btn, colors.HOVER)
    end)

    btn.MouseLeave:Connect(function()
        applyVisualState(btn, colors.IDLE)
    end)
end

local function injectButtons(originalBtn)
    if not originalBtn or originalBtn.Name == "FreeButton" or originalBtn.Name == "CopyButton" then
        return
    end

    local parent = originalBtn and originalBtn.Parent
    if not parent then return end

    if not parent:FindFirstChild("FreeButton") then
        task.wait(0.01)
        local freeBtn = originalBtn:Clone()
        freeBtn.Name = "FreeButton"
        freeBtn.Parent = parent
        decorateButton(freeBtn, "Free", (originalBtn.ZIndex or 1) + 10)
        wireHover(freeBtn, COLORS)

        freeBtn.Activated:Connect(function()
            local id = LastPrompt.Id
            if not id then return end

            applyVisualState(freeBtn, COLORS.HOVER)
            finishPurchase(id)
            applyVisualState(freeBtn, COLORS.IDLE)
            toggleRobloxMenu()
        end)
    end

    if not isSettingEnabled("CopyButton") then
        local existingCopy = parent:FindFirstChild("CopyButton")
        if existingCopy then
            existingCopy:Destroy()
        end
        return
    end

    if parent:FindFirstChild("CopyButton") then
        return
    end

    task.wait(0.01)
    local copyBtn = originalBtn:Clone()
    copyBtn.Name = "CopyButton"
    copyBtn.Parent = parent

    local freeBtn = parent:FindFirstChild("FreeButton")
    decorateButton(copyBtn, "Copy", freeBtn and freeBtn.ZIndex or ((originalBtn.ZIndex or 1) + 10), COPY_COLORS)
    wireHover(copyBtn, COPY_COLORS)
    positionCopyButton(freeBtn, copyBtn, parent)

    copyBtn.Activated:Connect(function()
        local id = LastPrompt.Id
        if not id then return end

        local operationText = buildPurchaseOperation(id)
        local copied = pcall(function()
            setclipboard(operationText)
        end)

        if copied then
            applyVisualState(copyBtn, COPY_COLORS.HOVER)
            task.wait(0.05)
        end
        applyVisualState(copyBtn, COPY_COLORS.IDLE)
    end)
end

local function getActions(foundation)
    local actions = foundation:FindFirstChild("SafeAreaFrame")
    actions = actions and actions:FindFirstChild("OverlayPortal")
    actions = actions and actions:FindFirstChild("SheetContainer")
    actions = actions and actions:FindFirstChild("Frame")
    actions = actions and actions:FindFirstChild("Sheet")
    actions = actions and actions:FindFirstChild("Content")
    actions = actions and actions:FindFirstChild("Actions")
    return actions or foundation:FindFirstChild("Actions", true)
end

local function scanActions(actionsFolder)
    for _, child in ipairs(actionsFolder:GetChildren()) do
        if tonumber(child.Name) then
            for _, inner in ipairs(child:GetDescendants()) do
                if inner:IsA("ImageButton") then
                    injectButtons(inner)
                end
            end
        end
    end
end

task.spawn(function()
    while true do
        if RuntimeState and RuntimeState.runId ~= CURRENT_RUN_ID then
            break
        end

        for _, child in ipairs(CoreGui:GetChildren()) do
            if child.Name == "FoundationOverlay" then
                local actions = getActions(child)
                if actions then
                    scanActions(actions)
                end
            end
        end
        task.wait(0.15)
    end
end)
