-- by 7yd7
--[[
getgenv().Settings = {
    CopyButton = false,
    -------------------
    AutoButton = false,
    AutoInterval = 0.1,
    -------------------
    InstantPurchase = false,
    AutoMassPurchase = false,
    ShowDebug = false,
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
local SECONDARY_BUTTON_DELAY = 0.03
local LastPrompt = { Id = nil, Type = nil, Nonce = 0 }
local LastInstant = { PromptNonce = -1 }
local SETTINGS_DEFAULTS = {
    CopyButton = false,
    AutoButton = false,
    AutoInterval = 0.3,
    InstantPurchase = false,
    ShowDebug = false,
    AutoMassPurchase = false,
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
    local handled = false
    pcall(function()
        for _, child in ipairs(CoreGui:GetChildren()) do
            if child.Name == "FoundationOverlay" and child:IsA("ScreenGui") and child.Enabled then
                local backdrop = child:FindFirstChild("Backdrop", true)
                if backdrop and backdrop:IsA("GuiButton") then
                    if type(firesignal) == "function" then
                        firesignal(backdrop.MouseButton1Click)
                        handled = true
                        break
                    end
                end
                
                local closeBtn = child:FindFirstChild("CloseButton", true) or child:FindFirstChild("Close", true)
                if closeBtn and closeBtn:IsA("GuiButton") then
                    if type(firesignal) == "function" then
                        firesignal(closeBtn.MouseButton1Click)
                        handled = true
                        break
                    end
                end
            end
        end
    end)
    
    if not handled then
        pcall(function()
            GuiService:SetMenuIsOpen(true)
            GuiService:SetMenuIsOpen(false)
        end)
    end
end

local DebugLog = { Lines = {} }
local function addLog(name, id, price)
    local timestamp = os.date("%H:%M:%S")
    local logEntry = string.format("[%s] %s | %s | %s", timestamp, tostring(name), string.sub(tostring(id), 1, 10), tostring(price or "0"))
    table.insert(DebugLog.Lines, 1, logEntry)
    if #DebugLog.Lines > 50 then table.remove(DebugLog.Lines) end
    if DebugLog.OnUpdate then DebugLog.OnUpdate(DebugLog.Lines) end
    print("LOG:", logEntry)
end

local function runMassPurchase()
    addLog("Mass Purchase Starting", 0, 0)
    task.spawn(function()
        local uid = (game.GameId ~= 0 and game.GameId) or game.UniverseId
        if uid == 0 then pcall(function() uid = MarketplaceService:GetProductInfo(game.PlaceId).UniverseId end) end
        
        pcall(function()
            for _, v in pairs(MarketplaceService:GetDeveloperProductsAsync():GetCurrentPage()) do
                MarketplaceService:SignalPromptProductPurchaseFinished(LocalPlayer.UserId, v.ProductId, true)
                task.wait(0.05)
            end
        end)
        addLog("Mass purchase complete", 0, 0)
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
        pcall(function() MarketplaceService:SignalPromptPremiumPurchaseFinished(true) end)
    end

    pcall(function()
        local it = (LastPrompt.Type == "GamePass") and Enum.InfoType.GamePass or Enum.InfoType.Product
        local info = MarketplaceService:GetProductInfo(id, it)
        addLog(info.Name, id, info.PriceInRobux or 0)
    end)
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

        if isSettingEnabled("InstantPurchase") then
            task.spawn(function()
                task.wait(0.05)
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
        local baseOrder = template and (template.LayoutOrder or 0) or 0
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
            task.wait(0.1)
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
            task.wait(0.15)
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
            while child and child.Parent and isCurrentRun() and isSettingEnabled("InstantPurchase") do
                local safeArea = child:FindFirstChild("SafeAreaFrame")
                local portal = safeArea and safeArea:FindFirstChild("OverlayPortal")

                if portal then
                    executeInstant()
                end
                task.wait(0.05)
            end
        end)
        return
    end

    local actions = getActions(child)
    if actions then
        scanActions(actions)
    else
        local conn
        conn = trackConnection(child.DescendantAdded:Connect(function()
            local actions = getActions(child)
            if actions then
                if conn then conn:Disconnect() end
                scanActions(actions)
            end
        end))
        task.delay(10, function()
            if conn then conn:Disconnect() end
        end)
    end
end

trackConnection(CoreGui.DescendantAdded:Connect(handleOverlay))
for _, child in ipairs(CoreGui:GetDescendants()) do
    task.spawn(handleOverlay, child)
end
startInstantStateWatcher()
startOverlayRescanLoop()

local function createSettingsUI()
    local gui = Instance.new("ScreenGui", CoreGui)
    gui.Name = "FGSettings"

    local main = Instance.new("Frame", gui)
    main.AnchorPoint, main.Position, main.Size = Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0, 300, 0, 240)
    main.BackgroundColor3, main.BackgroundTransparency, main.Visible = Color3.fromRGB(15, 15, 15), 0.1, false
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color, stroke.Thickness = Color3.fromRGB(45, 45, 45), 1

    local close = Instance.new("TextButton", main)
    close.Size, close.Position, close.Text = UDim2.new(0, 30, 0, 30), UDim2.new(1, -35, 0, 5), "X"
    close.BackgroundTransparency, close.TextColor3, close.Font, close.TextSize = 1, Color3.new(1, 1, 1), 3, 18
    close.Activated:Connect(function() main.Visible = false end)

    local content = Instance.new("ScrollingFrame", main)
    content.Position, content.Size, content.BackgroundTransparency, content.BorderSizePixel = UDim2.new(0, 10, 0, 40), UDim2.new(1, -20, 0, 110), 1, 0
    content.ScrollBarThickness, content.CanvasSize = 0, UDim2.new(0, 0, 0, 0)
    local list = Instance.new("UIListLayout", content)
    list.Padding, list.SortOrder = UDim.new(0, 5), 2

    local dbp = Instance.new("ScrollingFrame", main)
    dbp.Position, dbp.Size, dbp.BackgroundColor3 = UDim2.new(0, 10, 1, -80), UDim2.new(1, -20, 0, 70), Color3.new(0, 0, 0)
    dbp.ScrollBarThickness, dbp.CanvasSize = 2, UDim2.new(0, 0, 0, 0)
    Instance.new("UICorner", dbp).CornerRadius = UDim.new(0, 4)

    local function toggle(name, text, val, cb)
        local f = Instance.new("Frame", content)
        f.Size, f.BackgroundTransparency = UDim2.new(1, 0, 0, 25), 1
        local l = Instance.new("TextLabel", f)
        l.Size, l.Text, l.TextColor3, l.TextSize, l.XAlignment, l.BackgroundTransparency = UDim2.new(0.7, 0, 1, 0), text, Color3.new(0.8, 0.8, 0.8), 12, 0, 1
        local b = Instance.new("TextButton", f)
        b.AnchorPoint, b.Position, b.Size = Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.new(0, 34, 0, 16)
        b.BackgroundColor3, b.Text, b.BorderSizePixel = val and Color3.new(0, 1, 0.4) or Color3.new(0.2, 0.2, 0.2), "", 0
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        b.Activated:Connect(function()
            val = not val
            b.BackgroundColor3 = val and Color3.new(0, 1, 0.4) or Color3.new(0.2, 0.2, 0.2)
            cb(val)
        end)
    end

    local function setS(k, v)
        local s = getgenv().Settings or {}
        s[k] = v
        getgenv().Settings = s
    end

    local s = getSettings()
    toggle("Copy", "Copy Button", s.CopyButton, function(v) setS("CopyButton", v) end)
    toggle("Auto", "Auto Button", s.AutoButton, function(v) setS("AutoButton", v) end)
    toggle("Inst", "Instant Mode", s.InstantPurchase, function(v) setS("InstantPurchase", v) end)
    toggle("Mass", "Mass Buy All", s.AutoMassPurchase, function(v) setS("AutoMassPurchase", v); if v then runMassPurchase() end end)

    DebugLog.OnUpdate = function(lines)
        for _, c in ipairs(dbp:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
        for _, t in ipairs(lines) do
            local l = Instance.new("TextLabel", dbp)
            l.Size, l.Text, l.TextColor3, l.TextSize, l.XAlignment, l.BackgroundTransparency = UDim2.new(1, -5, 0, 14), t, Color3.new(0.6, 0.6, 0.6), 10, 0, 1
            l.Font = 4
        end
        dbp.CanvasSize = UDim2.new(0, 0, 0, #lines * 15)
    end
    return gui
end

pcall(createSettingsUI)

if getSettings().AutoMassPurchase then
    task.spawn(runMassPurchase)
end
