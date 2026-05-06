-- by 7yd7
--[[
getgenv().Settings = {
    CopyButton = false,
    -------------------
    AutoButton = false,
    AutoInterval = 0.1
}
]]

local CoreGui = game:GetService("CoreGui")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UIS = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local COLORS = {
    IDLE = Color3.fromRGB(34, 214, 78),
    HOVER = Color3.fromRGB(42, 232, 90),
}
local COPY_COLORS = {
    IDLE = Color3.fromRGB(255, 154, 46),
    HOVER = Color3.fromRGB(255, 176, 84),
}
local AUTO_COLORS = {
    IDLE = Color3.fromRGB(210, 72, 72),
    HOVER = Color3.fromRGB(232, 98, 98),
}
local TWEEN_SPEED = TweenInfo.new(0.045, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LastPrompt = { Id = nil, Type = nil }
local SETTINGS_DEFAULTS = {
    CopyButton = false,
    AutoButton = false,
    AutoInterval = 0.3,
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
local AutoLoopState = { Running = false, ThreadId = 0, StopGui = nil }

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

local function positionButtonBelow(anchorBtn, btn, parent)
    if not anchorBtn then return end
    if parent:FindFirstChildOfClass("UIListLayout") then
        btn.LayoutOrder = (anchorBtn.LayoutOrder or 0) + 1
        return
    end
    btn.Position = anchorBtn.Position + UDim2.fromOffset(0, 42)
end

local function stopAutoLoop()
    AutoLoopState.Running = false
    AutoLoopState.ThreadId = AutoLoopState.ThreadId + 1
end

local function destroyAutoStopButton()
    if AutoLoopState.StopGui and AutoLoopState.StopGui.Parent then
        AutoLoopState.StopGui:Destroy()
    end
    AutoLoopState.StopGui = nil
end

local function startAutoLoop()
    if AutoLoopState.Running then return end
    AutoLoopState.Running = true
    AutoLoopState.ThreadId = AutoLoopState.ThreadId + 1
    local myThreadId = AutoLoopState.ThreadId
    task.spawn(function()
        while AutoLoopState.Running and AutoLoopState.ThreadId == myThreadId do
            local id = LastPrompt.Id
            if id then
                finishPurchase(id)
                toggleRobloxMenu()
            end
            local interval = getSettings().AutoInterval
            if type(interval) ~= "number" or interval <= 0 then
                interval = 0.3
            end
            task.wait(interval)
        end
    end)
end

local function makeDraggable(frame)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil
    local didDrag = false
    local DRAG_THRESHOLD = 6

    local function update(input)
        local delta = input.Position - dragStart
        if math.abs(delta.X) > DRAG_THRESHOLD or math.abs(delta.Y) > DRAG_THRESHOLD then
            didDrag = true
        end
        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            didDrag = false
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            update(input)
        end
    end)

    return function()
        local wasDragged = didDrag
        didDrag = false
        return wasDragged
    end
end

local function createAutoStopButton()
    destroyAutoStopButton()

    local gui = Instance.new("ScreenGui")
    local button = Instance.new("TextButton")
    local corner = Instance.new("UICorner")
    local icon = Instance.new("ImageLabel")
    local aspect = Instance.new("UIAspectRatioConstraint")

    gui.Name = "AutoStopButton"
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = CoreGui

    button.Name = "Button"
    button.Parent = gui
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.Position = UDim2.new(0.5, 0, 0, 34)
    button.Size = UDim2.new(0.039, 0, 0.069, 0)
    button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    button.BackgroundTransparency = 0.4
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.ZIndex = 99999999
    button.Text = ""

    corner.CornerRadius = UDim.new(0, 99999)
    corner.Parent = button

    icon.Parent = button
    icon.BackgroundTransparency = 1
    icon.Position = UDim2.new(0.1, 0, 0.1, 0)
    icon.Size = UDim2.new(0.8, 0, 0.8, 0)
    icon.Image = "rbxassetid://98003862321782"
    icon.ImageColor3 = Color3.fromRGB(255, 90, 90)

    aspect.Parent = button
    aspect.AspectRatio = 1

    local wasDragged = makeDraggable(button)

    button.Activated:Connect(function()
        if wasDragged() then
            return
        end
        stopAutoLoop()
        destroyAutoStopButton()
    end)

    AutoLoopState.StopGui = gui
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
    if not originalBtn or originalBtn.Name == "FreeButton" or originalBtn.Name == "CopyButton" or originalBtn.Name == "AutoButton" then
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
    elseif not parent:FindFirstChild("CopyButton") then
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

    if not isSettingEnabled("AutoButton") then
        local existingAuto = parent:FindFirstChild("AutoButton")
        if existingAuto then
            existingAuto:Destroy()
        end
        stopAutoLoop()
        destroyAutoStopButton()
        return
    end

    if parent:FindFirstChild("AutoButton") then
        return
    end

    task.wait(0.01)
    local autoBtn = originalBtn:Clone()
    autoBtn.Name = "AutoButton"
    autoBtn.Parent = parent

    local anchorBtn = parent:FindFirstChild("CopyButton") or parent:FindFirstChild("FreeButton")
    decorateButton(autoBtn, "Auto", (anchorBtn and anchorBtn.ZIndex) or ((originalBtn.ZIndex or 1) + 10), AUTO_COLORS)
    wireHover(autoBtn, AUTO_COLORS)
    positionButtonBelow(anchorBtn, autoBtn, parent)

    autoBtn.Activated:Connect(function()
        toggleRobloxMenu()

        if AutoLoopState.Running then
            stopAutoLoop()
            destroyAutoStopButton()
            return
        end

        startAutoLoop()
        createAutoStopButton()
        applyVisualState(autoBtn, AUTO_COLORS.HOVER)
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
