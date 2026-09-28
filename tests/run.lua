-- Run from the repository root: lua tests/run.lua
-- Tests use explicit GIANTS API stubs. They validate our logic against documented
-- contracts; they do not establish that the real game or GUI behaves identically.
local passed, failed = 0, 0

function test(name, fn)
    local ok, message = pcall(fn)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(message))
    end
end

function assertEqual(actual, expected, message)
    assert(actual == expected, (message or "Values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

function assertNear(actual, expected, tolerance, message)
    assert(type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 0.000001), message or "Numbers are not close")
end

function assertContains(value, part, message)
    assert(type(value) == "string" and string.find(value, part, 1, true), message or (tostring(value) .. " does not contain " .. tostring(part)))
end

function assertTrue(value, message)
    assert(value == true, message or "Expected true")
end

function assertFalse(value, message)
    assert(value == false, message or "Expected false")
end

local suites = {"tests/test_data.lua", "tests/test_property.lua", "tests/test_inventory.lua", "tests/test_report.lua", "tests/test_bootstrap.lua"}
for _, path in ipairs(suites) do
    local file = io.open(path, "r")
    if file ~= nil then
        file:close()
        local ok, message = pcall(dofile, path)
        if not ok then
            failed = failed + 1
            print("FAIL loading " .. path .. ": " .. tostring(message))
        end
    else
        failed = failed + 1
        print("FAIL missing required suite " .. path)
    end
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 or passed == 0 then
    os.exit(1)
end
