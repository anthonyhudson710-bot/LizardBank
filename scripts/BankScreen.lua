-- GIANTS owns GUI input contexts, focus dispatch and cursor restoration.
BankScreen = {}
local BankScreen_mt = Class(BankScreen, ScreenElement)
local MOD_NAME = g_currentModName
local function trace(event, data)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then BankDiagnostics.emit(event, data) end
end

function BankScreen.new(owner, customMt)
    local self = ScreenElement.new(nil, customMt or BankScreen_mt)
    self.owner = owner
    self.pages = {}
    self.pageIndex = 1
    trace("gui.construct", {ownerPresent = owner ~= nil})
    return self
end

function BankScreen:onGuiSetupFinished()
    BankScreen:superClass().onGuiSetupFinished(self)
    local buttons = {self.backButton, self.previousButton, self.nextButton, self.refreshButton, self.policyButton}
    for index, button in ipairs(buttons) do
        FocusManager:linkElements(button, FocusManager.LEFT, buttons[(index - 2) % #buttons + 1])
        FocusManager:linkElements(button, FocusManager.RIGHT, buttons[index % #buttons + 1])
    end
    trace("gui.focus.links", {buttons = #buttons, directionalLinks = #buttons * 2})
end

function BankScreen:onOpen()
    trace("gui.onOpen.begin", {isBackAllowed = self.isBackAllowed})
    BankScreen:superClass().onOpen(self)
    self.pageIndex = 1
    self:onClickRefresh()
    FocusManager:setFocus(self.refreshButton)
    trace("gui.onOpen.end", {pageCount = #self.pages, initialFocus = "refreshButton", nativeFocusConfirmation = "manual_required"})
end

function BankScreen:onClose()
    trace("gui.onClose.begin", {pageIndex = self.pageIndex, pageCount = #self.pages})
    self.pages = {}
    self.pageIndex = 1
    BankScreen:superClass().onClose(self)
    trace("gui.onClose.end", {pagesCleared = #self.pages == 0, nativeCursorAndControls = "manual_required"})
end

function BankScreen:onClickBack()
    trace("gui.back", {allowed = self.isBackAllowed})
    if self.isBackAllowed then
        self:changeScreen(nil)
    end
    return true
end

function BankScreen:onClickRefresh()
    if self.owner == nil then return true end
    trace("gui.refresh.begin", {pageIndex = self.pageIndex})
    local ok, result = pcall(function()
        local snapshot = self.owner:captureSnapshot()
        if self.policyButton ~= nil then
            local mode = snapshot.history and snapshot.history.mode or "standard"
            self.policyButton:setText(BankReport.getText(g_i18n, "lb_policyButton", MOD_NAME,
                BankReport.getText(g_i18n, "lb_mode_" .. mode, MOD_NAME)))
        end
        return BankReport.buildPages(snapshot, g_i18n, MOD_NAME)
    end)
    if ok then
        self.pages = result
        if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
            -- Preserve prepared text for every page, including unvisited pages.
            -- Rendering geometry and native navigation still need manual checks.
            BankDiagnostics.dump("reportPages", result)
        end
        if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() and BankValidation ~= nil then
            local valid, message = pcall(BankValidation.pages, result, BankReport.LINES_PER_PAGE, BankDiagnostics.check)
            BankDiagnostics.check("GUI_PAGE_VALIDATOR", valid and "PASS" or "FAIL", {error = not valid and tostring(message) or nil})
        end
    else
        -- Preserve neither stale figures nor a misleading successful timestamp.
        self.pages = {{title = BankReport.getText(g_i18n, "lb_title", MOD_NAME),
            text = BankReport.getText(g_i18n, "lb_error", MOD_NAME)}}
        Logging.error("[LizardBank] Report refresh failed: %s", tostring(result))
        trace("gui.refresh.error", {error = tostring(result), stalePagesDiscarded = true})
    end
    self.pageIndex = math.max(1, math.min(self.pageIndex, #self.pages))
    self:showPage()
    trace("gui.refresh.end", {ok = ok, pageCount = #self.pages, pageIndex = self.pageIndex})
    return true
end

function BankScreen:onClickPolicy()
    if self.owner ~= nil and type(self.owner.cyclePolicy) == "function" then self.owner:cyclePolicy() end
    return self:onClickRefresh()
end

function BankScreen:showPage()
    local page = self.pages[self.pageIndex]
    if page == nil then return end
    self.pageTitle:setText(page.title)
    self.reportText:setText(page.text)
    self.pageNumber:setText(BankReport.getText(g_i18n, "lb_page", MOD_NAME, self.pageIndex, #self.pages))
    trace("gui.page", {index = self.pageIndex, count = #self.pages, title = page.title, text = page.text})
    -- Keep controls focusable at boundaries; a focused button disappearing or
    -- disabling after navigation can otherwise strand controller focus.
end

function BankScreen:onClickPrevious()
    trace("gui.navigation", {direction = "previous", from = self.pageIndex})
    self.pageIndex = math.max(1, self.pageIndex - 1)
    self:showPage()
    return true
end

function BankScreen:onClickNext()
    trace("gui.navigation", {direction = "next", from = self.pageIndex})
    self.pageIndex = math.min(#self.pages, self.pageIndex + 1)
    self:showPage()
    return true
end

function BankScreen:delete()
    trace("gui.delete", {hadOwner = self.owner ~= nil, pages = #self.pages})
    self.owner = nil
    self.pages = {}
    BankScreen:superClass().delete(self)
end
