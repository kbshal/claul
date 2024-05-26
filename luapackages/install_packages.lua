local luarocks = require("luarocks.loader")

local packages = {
    "lua-dotenv",
    "lua-socket",
    "lua-json"
}

for _, package in ipairs(packages) do
    luarocks.install_rock(package)
end