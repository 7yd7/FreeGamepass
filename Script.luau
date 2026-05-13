-- by 7yd7
--[[
getgenv().Settings = {
    CopyButton = false,
    -------------------
    AutoButton = false,
    AutoInterval = 0.1,
    -------------------
    InstantPurchase = false,
    -------------------
    AutoMassPurchase = false,
    Debug = false
}
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local CoreGui = game:GetService("CoreGui")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UIS = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end
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
local SECONDARY_BUTTON_DELAY = 0.03
local NEW_OVERLAY_BUTTON_INJECT_DELAY = 0
local INSTANT_STATE_WATCH_INTERVAL = 0.03
local OVERLAY_RESCAN_INTERVAL = 0.03
local LastPrompt = { Id = nil, Type = nil, Nonce = 0 }
local LastInstant = { PromptNonce = -1 }
local SETTINGS_DEFAULTS = {
    CopyButton = false,
    AutoButton = false,
    AutoInterval = 0.3,
    InstantPurchase = false,
    AutoMassPurchase = false,
    Debug = false,
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
        local expectedType = type(defaultValue)
        if type(envSettings[key]) == expectedType then
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
        if type(env.__FreeGamepassRuntime.connections) == "table" then
            for _, conn in ipairs(env.__FreeGamepassRuntime.connections) do
                pcall(function()
                    if conn and conn.Disconnect then
                        conn:Disconnect()
                    end
                end)
            end
        end
        env.__FreeGamepassRuntime.connections = {}
        env.__FreeGamepassRuntime.runId = env.__FreeGamepassRuntime.runId + 1
        RuntimeState = env.__FreeGamepassRuntime
    end
end)

local CURRENT_RUN_ID = RuntimeState and RuntimeState.runId or os.clock()
local AutoLoopState = { Running = false, ThreadId = 0, StopGui = nil }
local ParentButtonState = setmetatable({}, { __mode = "k" })
local ScriptConnections = RuntimeState and RuntimeState.connections or {}
local HiddenOverlays = setmetatable({}, { __mode = "k" })

local function isCurrentRun()
    return not RuntimeState or RuntimeState.runId == CURRENT_RUN_ID
end

local function trackConnection(conn)
    if conn then
        table.insert(ScriptConnections, conn)
    end
    return conn
end

local function toggleRobloxMenu()
    pcall(function()
        local foundOverlay = false
        for _, child in ipairs(CoreGui:GetChildren()) do
            if child:IsA("ScreenGui") and child.Name == "FoundationOverlay" and child.Enabled then
                local saf = child:FindFirstChild("SafeAreaFrame")
                local portal = saf and saf:FindFirstChild("OverlayPortal")
                local backdrop = portal and portal:FindFirstChild("Backdrop")
                local sheet = portal and portal:FindFirstChild("SheetContainer")

                if backdrop and sheet then
                    foundOverlay = true
                    local info = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
                    TweenService:Create(backdrop, info, {BackgroundTransparency = 1}):Play()
                    local t = TweenService:Create(sheet, info, {Position = UDim2.new(0.5, 0, 0.5, 32)})
                    t:Play()
                    t.Completed:Connect(function()
                        GuiService:SetMenuIsOpen(true)
                        GuiService:SetMenuIsOpen(false)
                    end)
                    break
                end
            end
        end

        if not foundOverlay then
            GuiService:SetMenuIsOpen(true)
            GuiService:SetMenuIsOpen(false)
        end
    end)
end

pcall(function()
    local oldStopGui = CoreGui:FindFirstChild("AutoStopButton")
    if oldStopGui then
        oldStopGui:Destroy()
    end
end)

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


local function fireEventFallback(event, ...)
    if type(firesignal) == "function" then
        pcall(firesignal, event, ...)
    end
end

local function finishPurchase(id)
    if LastPrompt.Type == "GamePass" then
        local success = pcall(function()
            MarketplaceService:SignalPromptGamePassPurchaseFinished(LocalPlayer.UserId, id, true)
        end)
        if not success then
            fireEventFallback(MarketplaceService.PromptGamePassPurchaseFinished, LocalPlayer, id, true)
        end

    elseif LastPrompt.Type == "Product" then
        local success = pcall(function()
            MarketplaceService:SignalPromptProductPurchaseFinished(LocalPlayer.UserId, id, true)
        end)
        if not success then
            fireEventFallback(MarketplaceService.PromptProductPurchaseFinished, LocalPlayer.UserId, id, true)
        end

    elseif LastPrompt.Type == "Asset" then
        local success = pcall(function()
            MarketplaceService:SignalPromptPurchaseFinished(LocalPlayer.UserId, id, true)
        end)
        if not success then
            fireEventFallback(MarketplaceService.PromptPurchaseFinished, LocalPlayer, id, true)
        end

    elseif LastPrompt.Type == "Bundle" then
        local success = pcall(function()
            MarketplaceService:SignalPromptBundlePurchaseFinished(LocalPlayer.UserId, id, true)
        end)
        if not success then
            fireEventFallback(MarketplaceService.PromptBundlePurchaseFinished, LocalPlayer, id, true)
        end

    elseif LastPrompt.Type == "Premium" then
        local success = pcall(function()
            MarketplaceService:SignalPromptPremiumPurchaseFinished(true)
        end)
        if not success then
            fireEventFallback(MarketplaceService.PromptPremiumPurchaseFinished, true)
        end
    end
end

local function restoreHiddenOverlays()
    for overlay in pairs(HiddenOverlays) do
        pcall(function()
            if overlay and overlay.Parent and overlay:IsA("ScreenGui") then
                overlay.Enabled = true
            end
        end)
        HiddenOverlays[overlay] = nil
    end
end

local function restoreFoundationOverlayVisibility()
    for _, child in ipairs(CoreGui:GetDescendants()) do
        if child:IsA("ScreenGui") and child.Name == "FoundationOverlay" then
            pcall(function()
                child.Enabled = true
            end)
        end
    end
end

local function runInstantPurchase(id, options)
    if not isCurrentRun() or not isSettingEnabled("InstantPurchase") then return end

    local opts = options or {}
    if opts.hideOverlay and opts.overlay then
        pcall(function()
            if opts.overlay:IsA("ScreenGui") then
                opts.overlay.Enabled = false
                HiddenOverlays[opts.overlay] = true
            end
        end)
    end

    if opts.forceMenuToggle then
        toggleRobloxMenu()
    end

    if not id then return end
    if id ~= LastPrompt.Id then return end
    local promptNonce = LastPrompt.Nonce or 0
    if LastInstant.PromptNonce == promptNonce then
        return
    end
    LastInstant.PromptNonce = promptNonce

    finishPurchase(id)
    if not opts.forceMenuToggle then
        return
    end
end
local function capturePrompt(player, id, promptType)
    if not isCurrentRun() then return end
    if player == LocalPlayer then
        LastPrompt.Nonce = (LastPrompt.Nonce or 0) + 1
        LastPrompt.Id = id
        LastPrompt.Type = promptType

        if isSettingEnabled("Debug") then
            task.spawn(function()
                local infoType
                if promptType == "GamePass" then
                    infoType = Enum.InfoType.GamePass
                elseif promptType == "Product" then
                    infoType = Enum.InfoType.Product
                elseif promptType == "Asset" then
                    infoType = Enum.InfoType.Asset
                elseif promptType == "Bundle" then
                    infoType = Enum.InfoType.Bundle
                end
                
                if infoType then
                    local success, info = pcall(function()
                        return MarketplaceService:GetProductInfo(id, infoType)
                    end)
                    if success and info then
                        print(string.format("%s | %s | %s", tostring(info.Name), tostring(id), tostring(info.PriceInRobux or 0)))
                    else
                        print(string.format("Unknown | %s | 0", tostring(id)))
                    end
                else
                    print(string.format("Unknown | %s | 0", tostring(id)))
                end
            end)
        end

        if isSettingEnabled("InstantPurchase") then
            task.spawn(function()
                runInstantPurchase(id, { forceMenuToggle = false })
            end)
        end
    end
end

trackConnection(MarketplaceService.PromptGamePassPurchaseRequested:Connect(function(player, id)
    capturePrompt(player, id, "GamePass")
end))

trackConnection(MarketplaceService.PromptProductPurchaseRequested:Connect(function(player, id)
    capturePrompt(player, id, "Product")
end))

trackConnection(MarketplaceService.PromptPurchaseRequested:Connect(function(player, id)
    capturePrompt(player, id, "Asset")
end))

trackConnection(MarketplaceService.PromptBundlePurchaseRequested:Connect(function(player, id)
    capturePrompt(player, id, "Bundle")
end))

trackConnection(MarketplaceService.PromptPremiumPurchaseRequested:Connect(function(player)
    capturePrompt(player, 0, "Premium")
end))

local function buildPurchaseOperation(id)
    local code = "local MarketplaceService = game:GetService(\"MarketplaceService\")\n\n"

    if LastPrompt.Type == "GamePass" then
        return code .. string.format("MarketplaceService:SignalPromptGamePassPurchaseFinished(%d, %d, true)", LocalPlayer.UserId, id)
    elseif LastPrompt.Type == "Product" then
        return code .. string.format("MarketplaceService:SignalPromptProductPurchaseFinished(%d, %d, true)", LocalPlayer.UserId, id)
    elseif LastPrompt.Type == "Asset" then
        return code .. string.format("MarketplaceService:SignalPromptPurchaseFinished(%d, %d, true)", LocalPlayer.UserId, id)
    elseif LastPrompt.Type == "Bundle" then
        return code .. string.format("MarketplaceService:SignalPromptBundlePurchaseFinished(%d, %d, true)", LocalPlayer.UserId, id)
    elseif LastPrompt.Type == "Premium" then
        return code .. "MarketplaceService:SignalPromptPremiumPurchaseFinished(true)"
    end
    return ""
end

local function settleButtonPosition(anchorBtn, btn, parent, offsetY)
    if not anchorBtn or not btn or not parent then return end
    local hasListLayout = parent:FindFirstChildOfClass("UIListLayout") ~= nil
    if hasListLayout then
        btn.LayoutOrder = (anchorBtn.LayoutOrder or 0) + 1
        return
    end

    btn.Position = anchorBtn.Position + UDim2.fromOffset(0, offsetY or 0)
    task.defer(function()
        if btn.Parent ~= parent or anchorBtn.Parent ~= parent then return end
        btn.Position = anchorBtn.Position + UDim2.fromOffset(0, offsetY or 0)
        task.defer(function()
            if btn.Parent ~= parent or anchorBtn.Parent ~= parent then return end
            btn.Position = anchorBtn.Position + UDim2.fromOffset(0, offsetY or 0)
        end)
    end)
end

local function settleFreeButtonPosition(originalBtn, freeBtn, parent)
    if not originalBtn or not freeBtn or not parent then return end
    local hasListLayout = parent:FindFirstChildOfClass("UIListLayout") ~= nil
    if hasListLayout then
        freeBtn.LayoutOrder = (originalBtn.LayoutOrder or 0) + 1
        return
    end

    freeBtn.Position = originalBtn.Position
    task.defer(function()
        if freeBtn.Parent ~= parent or originalBtn.Parent ~= parent then return end
        freeBtn.Position = originalBtn.Position
        task.defer(function()
            if freeBtn.Parent ~= parent or originalBtn.Parent ~= parent then return end
            freeBtn.Position = originalBtn.Position
        end)
    end)
end

local function getInjectedButtonsBaseOrder(parent)
    local maxOrder = 0
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") and child.Name ~= "FreeButton" and child.Name ~= "CopyButton" and child.Name ~= "AutoButton" then
            local order = child.LayoutOrder or 0
            if order > maxOrder then
                maxOrder = order
            end
        end
    end
    return maxOrder
end

local function getParentState(parent)
    local state = ParentButtonState[parent]
    if not state then
        state = {}
        ParentButtonState[parent] = state
    end
    return state
end

local function layoutInjectedButtons(parent)
    if not parent then return end

    local state = getParentState(parent)
    local template = state.TemplateButton
    if not (template and template.Parent == parent) then
        template = nil
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("ImageButton") and child.Name ~= "FreeButton" and child.Name ~= "CopyButton" and child.Name ~= "AutoButton" then
                template = child
                break
            end
        end
        state.TemplateButton = template
    end

    local freeBtn = parent:FindFirstChild("FreeButton")
    local copyBtn = parent:FindFirstChild("CopyButton")
    local autoBtn = parent:FindFirstChild("AutoButton")
    local hasListLayout = parent:FindFirstChildOfClass("UIListLayout") ~= nil

    if hasListLayout then
        local baseOrder = getInjectedButtonsBaseOrder(parent)
        if freeBtn then freeBtn.LayoutOrder = baseOrder + 1 end
        if copyBtn then copyBtn.LayoutOrder = baseOrder + 2 end
        if autoBtn then autoBtn.LayoutOrder = baseOrder + 3 end
        return
    end

    if freeBtn and template then
        settleFreeButtonPosition(template, freeBtn, parent)
    end
    if copyBtn and freeBtn then
        settleButtonPosition(freeBtn, copyBtn, parent, 42)
    end
    if autoBtn then
        local anchorBtn = copyBtn or freeBtn
        if anchorBtn then
            settleButtonPosition(anchorBtn, autoBtn, parent, 42)
        end
    end
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

local function processParentButtons(parent)
    if not parent then return end
    local state = getParentState(parent)
    if state.Injecting then
        state.Dirty = true
        return
    end
    state.Injecting = true

    task.spawn(function()
        repeat
            state.Dirty = false
            local template = state.TemplateButton
            if not (template and template.Parent == parent) then
                state.Injecting = false
                return
            end

            if not parent:FindFirstChild("FreeButton") then
                local freeBtn = template:Clone()
                freeBtn.Name = "FreeButton"
                freeBtn.Parent = parent
                decorateButton(freeBtn, "Free", (template.ZIndex or 1) + 10)
                settleFreeButtonPosition(template, freeBtn, parent)
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

            task.defer(function()
                task.wait(SECONDARY_BUTTON_DELAY)
                if not isSettingEnabled("CopyButton") then
                    local existingCopy = parent:FindFirstChild("CopyButton")
                    if existingCopy then existingCopy:Destroy() end
                    return
                end
                if parent:FindFirstChild("CopyButton") then return end
                local templateBtn = state.TemplateButton
                if not (templateBtn and templateBtn.Parent == parent) then return end
                local copyBtn = templateBtn:Clone()
                copyBtn.Name = "CopyButton"
                copyBtn.Parent = parent
                local freeBtn = parent:FindFirstChild("FreeButton")
                decorateButton(copyBtn, "Copy", freeBtn and freeBtn.ZIndex or ((templateBtn.ZIndex or 1) + 10), COPY_COLORS)
                wireHover(copyBtn, COPY_COLORS)
                settleButtonPosition(freeBtn, copyBtn, parent, 42)
                copyBtn.Activated:Connect(function()
                    local id = LastPrompt.Id
                    if not id then return end
                    local operationText = buildPurchaseOperation(id)
                    local copied = pcall(function() setclipboard(operationText) end)
                    if copied then
                        applyVisualState(copyBtn, COPY_COLORS.HOVER)
                        task.wait(0.05)
                    end
                    applyVisualState(copyBtn, COPY_COLORS.IDLE)
                end)
            end)

            task.defer(function()
                task.wait(SECONDARY_BUTTON_DELAY)
                if not isSettingEnabled("AutoButton") then
                    local existingAuto = parent:FindFirstChild("AutoButton")
                    if existingAuto then existingAuto:Destroy() end
                    stopAutoLoop()
                    destroyAutoStopButton()
                    return
                end
                if parent:FindFirstChild("AutoButton") then return end
                local templateBtn = state.TemplateButton
                if not (templateBtn and templateBtn.Parent == parent) then return end
                local autoBtn = templateBtn:Clone()
                autoBtn.Name = "AutoButton"
                autoBtn.Parent = parent
                local anchorBtn = parent:FindFirstChild("CopyButton") or parent:FindFirstChild("FreeButton")
                decorateButton(autoBtn, "Auto", (anchorBtn and anchorBtn.ZIndex) or ((templateBtn.ZIndex or 1) + 10), AUTO_COLORS)
                wireHover(autoBtn, AUTO_COLORS)
                settleButtonPosition(anchorBtn, autoBtn, parent, 42)
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
            end)

            task.wait()
            layoutInjectedButtons(parent)
        until not state.Dirty

        state.Injecting = false
    end)
end

local function injectButtons(originalBtn)
    if not originalBtn or originalBtn.Name == "FreeButton" or originalBtn.Name == "CopyButton" or originalBtn.Name == "AutoButton" then
        return
    end
    local parent = originalBtn.Parent
    if not parent then return end
    local state = getParentState(parent)
    if not (state.TemplateButton and state.TemplateButton.Parent == parent) then
        state.TemplateButton = originalBtn
    end
    processParentButtons(parent)
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

local function scanAllFoundationOverlays()
    for _, child in ipairs(CoreGui:GetDescendants()) do
        if child:IsA("ScreenGui") and child.Name == "FoundationOverlay" then
            local actions = getActions(child)
            if actions then
                scanActions(actions)
            end
        end
    end
end

local ProcessedOverlays = setmetatable({}, { __mode = "k" })
local handleOverlay
local function startInstantStateWatcher()
    task.spawn(function()
        local wasEnabled = isSettingEnabled("InstantPurchase")
        if not wasEnabled then
            restoreHiddenOverlays()
            restoreFoundationOverlayVisibility()
            scanAllFoundationOverlays()
        end
        while isCurrentRun() do
            local isEnabled = isSettingEnabled("InstantPurchase")
            if isEnabled ~= wasEnabled then
                if not isEnabled then
                    LastInstant.PromptNonce = -1
                    restoreHiddenOverlays()
                    restoreFoundationOverlayVisibility()
                    scanAllFoundationOverlays()
                end
                for _, child in ipairs(CoreGui:GetDescendants()) do
                    if child:IsA("ScreenGui") and child.Name == "FoundationOverlay" then
                        task.spawn(handleOverlay, child, true)
                    end
                end
                wasEnabled = isEnabled
            end
            task.wait(INSTANT_STATE_WATCH_INTERVAL)
        end
    end)
end

local function startOverlayRescanLoop()
    task.spawn(function()
        while isCurrentRun() do
            if not isSettingEnabled("InstantPurchase") then
                for _, child in ipairs(CoreGui:GetDescendants()) do
                    if child:IsA("ScreenGui") and child.Name == "FoundationOverlay" then
                        local actions = getActions(child)
                        if actions then
                            scanActions(actions)
                        end
                    end
                end
            end
            task.wait(OVERLAY_RESCAN_INTERVAL)
        end
    end)
end

function handleOverlay(child, force)
    if child.Name ~= "FoundationOverlay" then return end
    local modeKey = isSettingEnabled("InstantPurchase") and "instant" or "buttons"
    if not force and ProcessedOverlays[child] == modeKey then return end
    ProcessedOverlays[child] = modeKey

    if isSettingEnabled("InstantPurchase") then
        local function executeInstant()
            local id = LastPrompt.Id
            runInstantPurchase(id, { hideOverlay = true, overlay = child, forceMenuToggle = true })
        end

        task.spawn(function()
            local function check()
                if not (child and child.Parent and isSettingEnabled("InstantPurchase")) then return true end
                local safeArea = child:FindFirstChild("SafeAreaFrame")
                local portal = safeArea and safeArea:FindFirstChild("OverlayPortal")
                if portal then
                    executeInstant()
                    return true
                end
                return false
            end

            if not check() then
                local conn
                conn = trackConnection(child.DescendantAdded:Connect(function()
                    if check() then
                        if conn then conn:Disconnect() end
                    end
                end))
            end
        end)
        return
    end

    local function scanButtonsWithDelay()
        if not (child and child.Parent and isCurrentRun() and not isSettingEnabled("InstantPurchase")) then return false end
        if not force then
            task.wait(NEW_OVERLAY_BUTTON_INJECT_DELAY)
        end
        if not (child and child.Parent and isCurrentRun() and not isSettingEnabled("InstantPurchase")) then return false end
        local actions = getActions(child)
        if not actions then return false end
        scanActions(actions)
        return true
    end

    if scanButtonsWithDelay() then
        return
    end

    local conn
    conn = trackConnection(child.DescendantAdded:Connect(function()
        if scanButtonsWithDelay() then
            if conn then conn:Disconnect() end
        end
    end))
    task.delay(10, function()
        if conn then conn:Disconnect() end
    end)
end

trackConnection(CoreGui.DescendantAdded:Connect(handleOverlay))
for _, child in ipairs(CoreGui:GetDescendants()) do
    task.spawn(handleOverlay, child)
end
startInstantStateWatcher()
startOverlayRescanLoop()

local function performAutoMassPurchase()
    if not isSettingEnabled("AutoMassPurchase") then return end
    task.spawn(function()
        local success, productsPage = pcall(function()
            return MarketplaceService:GetDeveloperProductsAsync()
        end)
        if success and productsPage then
            while true do
                local products = productsPage:GetCurrentPage()
                for _, info in ipairs(products) do
                    local id = info.ProductId
                    local name = info.Name or "Unknown"
                    local price = info.PriceInRobux or 0
                    
                    if isSettingEnabled("Debug") then
                        print(string.format("Product: %s | %s | %s", tostring(name), tostring(id), tostring(price)))
                    end
                    
                    local successSig = pcall(function()
                        MarketplaceService:SignalPromptProductPurchaseFinished(LocalPlayer.UserId, id, true)
                    end)
                    if not successSig then
                        fireEventFallback(MarketplaceService.PromptProductPurchaseFinished, LocalPlayer.UserId, id, true)
                    end
                    task.wait(0.1)
                end
                if productsPage.IsFinished then
                    break
                end
                pcall(function() productsPage:AdvanceToNextPageAsync() end)
            end
        end
        
        local HttpService = game:GetService("HttpService")
        local universeId = game.GameId
        if universeId == 0 then
            pcall(function()
                local res = game:HttpGet("https://apis.roblox.com/universes/v1/places/" .. tostring(game.PlaceId) .. "/universe")
                local data = HttpService:JSONDecode(res)
                if data and data.universeId then
                    universeId = data.universeId
                end
            end)
        end
        
        if universeId and universeId > 0 then
            pcall(function()
                local cursor = ""
                while cursor do
                    local url = "https://games.roblox.com/v1/games/" .. tostring(universeId) .. "/game-passes?limit=100"
                    if cursor ~= "" then
                        url = url .. "&cursor=" .. cursor
                    end
                    local res = game:HttpGet(url)
                    local data = HttpService:JSONDecode(res)
                    if data and data.data then
                        for _, gp in ipairs(data.data) do
                            local id = gp.id
                            local name = gp.name or "Unknown"
                            local price = gp.price or 0
                            
                            if isSettingEnabled("Debug") then
                                print(string.format("GamePass: %s | %s | %s", tostring(name), tostring(id), tostring(price)))
                            end
                            
                            local successSig = pcall(function()
                                MarketplaceService:SignalPromptGamePassPurchaseFinished(LocalPlayer.UserId, id, true)
                            end)
                            if not successSig then
                                fireEventFallback(MarketplaceService.PromptGamePassPurchaseFinished, LocalPlayer, id, true)
                            end
                            task.wait(0.1)
                        end
                        cursor = data.nextPageCursor
                    else
                        cursor = nil
                    end
                end
            end)
        end
    end)
end

performAutoMassPurchase()
